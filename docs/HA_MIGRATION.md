# Production HA Migration Runbook

Steps to convert the existing single-controller production cloud
(`controller1`, currently holds a manually-assigned VIP, no HAProxy)
to a 2-node active/active HA controller pair (`controller1` +
`controller2`) with minimal downtime.

This runbook assumes the cookbook is already at the
`ramereth/ha-controller` branch (or merged) and that you have read
[recipes/ha.rb](../recipes/ha.rb) and
[libraries/helpers.rb](../libraries/helpers.rb) for context.

The runbook is organized in four sections:

- **A. Preparation** — staging changes off-line; *no impact on prod*.
- **B. Cookbook deploy on `controller1`** — applies the new cookbook
  in non-HA mode; brief (~1–5s) service reloads/restarts, *no
  keepalived/HAProxy behavior change yet*.
- **C. HA cutover** — keepalived takes the VIP, HAProxy fronts the
  APIs, `controller2` joins the cluster. *This is the main outage
  window (~30s–2m).*
- **D. Validation & finalize** — failover test, router migration,
  cleanup.

## Target Architecture

| Component | Today (`controller1` only) | After (`controller1` + `controller2`) |
| --- | --- | --- |
| Controllers | 1 active | 2 active/active |
| VIP | Manually-assigned IP on `controller1` | keepalived-managed, floats |
| API frontend | Apache binds `0.0.0.0` directly | HAProxy on VIP → Apache on per-host private IP |
| RabbitMQ | Single broker on `controller1` | Mnesia cluster across both controllers |
| Memcached | Single instance on `controller1` | Two instances, clients see both |
| Cinder volume | Single active | Active/active via `cluster` + tooz |
| Neutron L3 | Single agent | `l3_ha = True`, `max_l3_agents_per_router = 2` |
| MariaDB | External `osl-mysql` primary | **Unchanged** (HA out of scope) |

## Prerequisites

- [ ] `controller2` host provisioned, OS installed, on the same L2
      segment as `controller1` (VRRP requires multicast).
- [ ] Forward + reverse DNS resolves for `controller2.<domain>`. Both
      controllers can resolve each other's FQDN to the
      **management/data** IP (not the VIP). RabbitMQ Mnesia is fragile
      if FQDNs don't agree.
- [ ] Each controller has a per-host private IP reserved for Apache /
      backend services to bind to (separate from the VIP). These go in
      `ha.api_listen_ip`.
- [ ] VIPs (v4 + v6) reserved. Today's manual VIP is reused — the
      keepalived takeover replaces the static assignment.
- [ ] Unique `virtual_router_id` on this L2 segment (collisions with
      other VRRP groups will silently corrupt state).
- [ ] Generated secrets ready:
  - VRRP `auth_pass` (any string, ≤8 chars used by VRRP)
  - HAProxy stats `stats_user` / `stats_pass`
  - Erlang cookie for RabbitMQ (20+ chars, alphanumeric, no quotes —
    must be identical on both nodes)
- [ ] Maintenance window scheduled for **Section C** only. Plan for
      **30s–2m** of API unavailability during step C2.

---

# A. Preparation (no production impact)

These phases stage everything off-line. Nothing here deploys to prod.

## A1 — Upload cookbook to chef server

1. Merge / tag the `ramereth/ha-controller` branch.
2. `berks upload` (or equivalent) to push the new cookbook + deps to
   the chef server. **Do not run `chef-client` yet.**
3. Confirm `osl-openstack`, `osl-haproxy`, `osl-keepalived` versions
   on the chef server match what's in `Berksfile.lock`.

## A2 — Draft the data-bag merge request (DON'T MERGE YET)

The HA recipe is gated on `safe_dig(os_secrets, 'ha')` — see
[recipes/controller.rb:23](../recipes/controller.rb#L23). Until the
`ha` block exists in the deployed data bag, nothing changes for any
node that runs chef.

Open a merge request against the data-bag repo for the prod cloud's
`openstack` data bag item (your `x86`-suffixed item, or whichever
matches `database_server.suffix`). The MR adds:

```jsonc
{
  "ha": {
    "keepalived": {
      "primary": {
        "controller1.<domain>": true,
        "controller2.<domain>": false
      },
      "interface": {
        "controller1.<domain>": "<vrrp-iface>",
        "controller2.<domain>": "<vrrp-iface>"
      },
      "priority": {
        "controller1.<domain>": 100,
        "controller2.<domain>": 90
      },
      "virtual_router_id": <unique-1-255>,
      "auth_pass": "<vrrp-secret>",
      "vip_v4": "<existing-manual-vip-v4>",
      "vip_v6": "<existing-manual-vip-v6>"
    },
    "api_listen_ip": {
      "controller1.<domain>": "<controller1-private-ip>",
      "controller2.<domain>": "<controller2-private-ip>"
    },
    "haproxy": {
      "stats_user": "<user>",
      "stats_pass": "<pass>"
    }
  }
}
```

In the same MR, convert these single-string fields to **arrays**
listing both controllers (the helpers accept either form — see
`openstack_transport_url` and `openstack_memcached_endpoints` in
[libraries/helpers.rb](../libraries/helpers.rb)):

```jsonc
{
  "messaging": {
    "endpoint": ["controller1.<domain>", "controller2.<domain>"],
    "user":    "openstack",
    "pass":    "...",
    "cookie":       "<erlang-cookie>",
    "primary_node": "rabbit@controller1.<domain>"
  },
  "memcached": {
    "endpoint": [
      "controller1.<domain>:11211",
      "controller2.<domain>:11211"
    ]
  },
  "network": {
    "ha": true
    // ...existing keys
  },
  "block-storage": {
    "cluster": "<cluster-name>"
    // ...existing keys
  }
}
```

`<cluster-name>` is an arbitrary identifier (e.g. `prod` or
`cloud-name`). It's what cinder-volume services register themselves
under so they form an active/active cluster — see
[templates/cinder.conf.erb:13-27](../templates/cinder.conf.erb#L13-L27).
Once both controllers run with the same value, `cinder-manage cluster
list` will show one cluster with two services bound (verified in D3).

Notes:

- `messaging.primary_node` is the FQDN-form Erlang node name of the
  **existing** broker (`controller1`). New nodes (`controller2`) join
  *this* node's cluster; `controller1` never tries to join itself.
- `network.ha = true` flips
  [templates/neutron.conf.erb:14-16](../templates/neutron.conf.erb#L14-L16).
  Existing routers stay non-HA until you migrate them (D2).
- **Do NOT set `messaging.quorum_queues` in this MR.** Quorum queues
  (durable, Raft-replicated — the real fix for the classic-queue loss
  that desyncs the cluster on a node restart) are gated on a *separate*
  `messaging.quorum_queues` flag, not the `ha` block, on purpose: a
  queue's type is immutable and a quorum queue's replica set is fixed
  at declaration, so the queues must be created only once **both**
  controllers are clustered. Enabling them mid-cutover would error out
  and/or yield 1-replica queues. Leave the flag off here and enable it
  as a deliberate post-cutover step — see
  [C4 — Enable RabbitMQ quorum queues](#c4--enable-rabbitmq-quorum-queues).
- Don't remove the old single-string forms — *replace* them. The old
  string form will not be valid once the keys become arrays.
- Get the MR reviewed and approved, but **leave it un-merged** until
  step C1. Merging is what deploys.

## A3 — Bootstrap `controller2` with an empty run list

1. Bootstrap `controller2` against the chef server with an **empty
   run_list** (or an OS-baseline-only role).
2. Run `chef-client` once. Confirm:
   - Node registered with the chef server.
   - OHAI sees the right `fqdn`, `ipaddress`, interfaces.
   - Both controllers resolve each other's FQDN (DNS or
     `/etc/hosts`).
3. Pre-installing RabbitMQ on `controller2` is **not** required — the
   full HA run list (step C3) installs everything.

---

# B. Cookbook deploy on `controller1` (no HA behavior, brief restarts)

This is a normal cookbook upgrade. Because the data-bag MR from A2 is
not merged yet, `safe_dig(os_secrets, 'ha')` returns nil and
`osl-openstack::ha` stays skipped. But the cookbook also tightens
some templates outside the HA gate — `Listen *:5000` instead of
`Listen 5000`, `bind_host = *` instead of an absent line, etc. The
behavior is identical (`*` is the same wildcard bind as before), but
the **text** of the config files differs, so Chef will reload Apache
and restart a few native daemons.

Doing this step separately from the cutover means:

- the cosmetic service-restart blips happen during a normal cookbook
  upgrade window, not during the keepalived takeover, and
- if something about the cookbook upgrade itself misbehaves, you
  debug it with keepalived/HAProxy still out of the picture.

## B1 — Run chef on `controller1`

```bash
sudo cinc-client 2>&1 | tee /root/ha-prestage.log
```

Expected restarts/reloads on this run:

| File | Old | New | Impact |
| --- | --- | --- | --- |
| `node['osl-apache']['listen']` | `["80","443"]` | `["*:80","*:443"]` | Apache reload |
| `wsgi-*.conf.erb` (keystone, nova-api, nova-metadata, placement, cinder-api) | `Listen 5000` etc. | `Listen *:5000` etc. | Apache reload |
| `glance-api.conf.erb` | (no `bind_host`) | `bind_host = *` | glance-api restart |
| `neutron.conf.erb` | (no `bind_host`) | `bind_host = *` | neutron-server restart |
| `heat.conf.erb` | (no `bind_host`) | `bind_host = *` | heat-api / heat-api-cfn restart |
| `nova.conf.erb` | (no `novncproxy_host`) | `novncproxy_host = *` | nova-novncproxy restart |

Each is a ~1–5s blip for that specific API. Stagger or accept; the
cluster as a whole stays serving.

## B2 — Verify and run chef a second time

```bash
sudo cinc-client
```

The second run should be idempotent — no resources updated. If
anything still updates, investigate before moving to Section C.

Confirm:

- All native daemons running.
- `openstack endpoint list` works.
- The existing manually-assigned VIP is still bound on
  `<vrrp-iface>`.

---

# C. HA cutover (THE OUTAGE WINDOW)

This is the maintenance window. Steps C1–C3 take **~30s–2m** of API
unavailability total (mostly during C2's service restarts); C4 adds a
longer outage while all OpenStack daemons stop for the RabbitMQ purge.

**Before you begin, pause the chef-client cron on both controllers and
every hypervisor** so an automatic converge can't fire mid-cutover and
restart services or recreate queues out from under you. The cron fires
at the top of the hour and at :30 and a run takes up to ~10 minutes, so
**don't begin a stop/restart step inside the :00–:10 or :30–:40
windows**, and confirm none is in flight (`pgrep -af chef-client`)
before starting. Re-enable it in D4 once the migration is verified.

## C1 — Merge the data-bag MR

Merge the MR from A2 and confirm chef server / chef-zero is now
serving the data bag with the `ha` block. Until the next chef-client
run on `controller1`, the bag exists but the recipe hasn't reacted.

## C2 — Cutover `controller1`

This run installs keepalived + HAProxy, flips Apache from wildcard to
per-host IP, and restarts the native API daemons (glance-api,
neutron-server, heat-api, heat-cfn, nova-novncproxy) so they release
their `0.0.0.0:port` sockets before HAProxy tries to bind the VIP on
the same port.

1. **Drain the manual VIP** on `controller1`. The VIP must not
   already be bound to the interface when keepalived starts
   (keepalived will not steal an address it didn't put there, and
   the duplicate bind will look like split-brain). Don't run a manual
   `ip addr del` — instead **remove the VIP from the network data bag**
   so chef tears it down for you: drop the VIP entry from the
   interface definition and merge that change before the cutover run.
   The chef run in C2 then converges the interface without the VIP,
   leaving it free for keepalived to claim.

2. **Pre-cutover snapshot** for rollback comparison:

   ```bash
   ip addr show           > /root/pre-ha-ipaddr.txt
   ss -tlnp               > /root/pre-ha-listening.txt
   rabbitmqctl status     > /root/pre-ha-rabbit.txt
   openstack endpoint list > /root/pre-ha-endpoints.txt
   ```

3. **Stop the listeners that hold the API ports** *before* the chef
   run. HAProxy is going to bind the VIP on the same ports these
   processes currently hold on `0.0.0.0`. If they're still listening
   when HAProxy starts, the bind fails and the run aborts. Stop Apache
   and every native daemon that isn't fronted by Apache:

   ```bash
   systemctl stop httpd
   systemctl stop \
     openstack-glance-api \
     neutron-server \
     openstack-heat-api \
     openstack-heat-api-cfn \
     openstack-nova-novncproxy
   ```

   Then **confirm nothing is still bound** to the API ports.
   `neutron-server` in particular doesn't always release its socket
   on stop — its worker processes can linger:

   ```bash
   ss -tlnp | grep -E ':(5000|8774|8776|9292|9696|8004|8000|6080|80|443) '
   ```

   If anything is still listening, kill the leftover PIDs (the
   `pid=` is shown in the `ss` output) and re-check:

   ```bash
   kill -9 <pid>
   ```

4. **Clear the old Apache vhosts** so the first chef run can re-render
   them on the per-host listen IP without the package-default
   wildcard vhosts racing HAProxy for the port:

   ```bash
   rm -f /etc/httpd/sites-enabled/*
   ```

5. **Run chef on `controller1`**:

   ```bash
   sudo cinc-client 2>&1 | tee /root/ha-cutover.log
   ```

   Things to expect in the log (in order):
   - `osl-keepalived` installs, drops `keepalived.conf` includes for
     `openstack-ipv4` / `openstack-ipv6` / `openstack` sync_group,
     starts keepalived. The VIP appears on the wire within ~3s.
   - `osl-haproxy::install` installs the package; the recipe
     immediately overwrites the package-default
     `/etc/haproxy/haproxy.cfg` with a stub that binds only
     `127.0.0.1:18999` (haproxy 3.x rejects no-proxy configs, see
     [recipes/ha.rb:86-114](../recipes/ha.rb#L86-L114)).
   - Apache vhosts re-render with `Listen <api_listen_ip>:<port>` and
     reload.
   - `glance-api`, `neutron-server`, `heat-api`, `heat-api-cfn`,
     `nova-novncproxy` each restart and rebind to the per-host IP.
   - At end of run: HAProxy reloads with the real config (all
     listeners for the OpenStack APIs on the VIP). The
     `service[haproxy_post_daemons_restart]` resource queues a
     delayed restart that fires after the native daemons have
     released their wildcard sockets.

6. **Verify on `controller1`**:

   ```bash
   # VIP held here
   ip -4 addr show | grep <vip_v4>
   ip -6 addr show | grep <vip_v6>

   # Apache on per-host IP, not 0.0.0.0
   ss -tlnp | grep -E ':(5000|8774|8776|9292|9696|8004|8000|6080|80|443) '

   # HAProxy on VIP
   ss -tlnp | grep haproxy

   # Stats UI
   curl -u <stats_user>:<stats_pass> http://<api_listen_ip>:9000/

   # Service smoke test (against the VIP, which now == HAProxy)
   openstack endpoint list
   openstack server list
   ```

7. **Second chef pass** on `controller1`. Must be idempotent — only
   `service[haproxy] :reload` (if any haproxy bind set changed)
   should fire. Anything else updating means an ordering bug.

If anything in this step fails badly, see [Rollback](#rollback).

## C3 — Bring `controller2` online

1. Add `controller2` to the same role / run_list that `controller1`
   uses (typically `role[osl-openstack-controller]` or whatever wraps
   `recipe[osl-openstack::controller]`).

2. Run chef on `controller2`:

   ```bash
   sudo cinc-client 2>&1 | tee /root/ha-join.log
   ```

   Watch for:
   - keepalived starts but does **not** take the VIP (priority 90 vs
     `controller1`'s 100). On the wire, `controller2` sends VRRP
     advertisements but stays BACKUP.
   - RabbitMQ installs, the `osl_openstack_messaging` resource (see
     [resources/messaging.rb](../resources/messaging.rb)) writes
     `/var/lib/rabbitmq/.erlang.cookie`, sets `USE_LONGNAME=true` and
     `NODENAME=rabbit@controller2.<domain>` in `rabbitmq-env.conf`,
     restarts rabbit, then runs `rabbitmqctl join_cluster
     rabbit@controller1.<domain>`. The join wipes `controller2`'s
     local mnesia and copies schema from `controller1` —
     non-disruptive to `controller1`'s existing connections.
   - Apache binds `controller2`'s `api_listen_ip` per-host IP.
   - HAProxy on `controller2` binds the VIP listeners using
     `ip_nonlocal_bind=1` (it doesn't currently hold the VIP).

3. **Verify the cluster**:

   ```bash
   # On either node
   rabbitmqctl cluster_status
   # Should show both rabbit@controller1.<domain> and rabbit@controller2.<domain>

   # On controller1 (HAProxy stats — both backends should be UP)
   curl -u <stats_user>:<stats_pass> http://<controller1-api-listen-ip>:9000/

   # API still works
   openstack endpoint list
   ```

4. **Expect a degraded control plane until C4 — don't bounce daemons
   here.** The `join_cluster` step restarts RabbitMQ underneath the
   already-running controller daemons (conductor, scheduler,
   neutron-server, the neutron/ceilometer agents) and the hypervisor
   agents. oslo.messaging reconnects but can come back half-dead: it
   re-declares its `*_fanout_*` queues (so casts/notifications work)
   yet never re-subscribes to its shared RPC *call* queue — so every
   `call` silently times out (`MessagingTimeout: Timed out waiting for
   a reply ...`, "Timed out waiting for nova-conductor") while the
   process looks healthy. **Don't restart them here**: C4 (next) stops,
   purges, and restarts every daemon cleanly, which resolves this *and*
   migrates to quorum in one pass — a restart now would just be undone
   seconds later.

   Only if you must pause between C3 and C4 (leaving `controller2`
   serving traffic on classic queues) do you need to restore RPC in the
   interim: restart the full controller daemon set plus `httpd` (the
   stop list in [C4 step 2](#c4--enable-rabbitmq-quorum-queues)), then
   `openstack-nova-compute` / `openstack-ceilometer-compute` /
   `neutron-linuxbridge-agent` on every hypervisor, and confirm the
   shared `conductor` call queue is
   consumed from both nodes:
   `rabbitmqctl list_queues name consumers | grep -E '^conductor[[:space:]]'`.

---

## C4 — Enable RabbitMQ quorum queues

> **Superseded for production.** Enabling quorum on the controllers'
> *2-node* RabbitMQ cluster yields 2-member queues that tolerate **zero**
> failures — rebooting either controller drops below majority and NACKs
> publishes. The production answer is the shared **3-node** tier in
> [SHARED_MESSAGING_TIER.md](SHARED_MESSAGING_TIER.md). Only run C4
> in-place if this cloud's RabbitMQ cluster has **≥3 members**; on a
> 2-node controller pair it is not real HA.

Do this in the **same maintenance window as C3**, immediately after the
C3 cluster-health check and **before the D1 failover test**. Ordering
matters: running D1 against classic queues would validate failover
behavior that isn't your production config, and every minute the
cluster runs on classic queues is exposure to the node-restart desync
this whole exercise is fixing. Requires both rabbit nodes clustered
with `partitions: (none)` (verified at the end of C3).

**Why it's its own step and not the `ha` block.** Quorum queues
(durable, Raft-replicated) are what stop a clustered rabbit node from
losing its non-replicated transient queues — and desyncing the cluster
— when it restarts. Two RabbitMQ rules force *when* they can be turned
on:

- A queue's **type is immutable** — you can't convert classic→quorum in
  place, so the existing queues must be deleted and redeclared
  (declaring over a surviving classic queue fails `PRECONDITION_FAILED`).
- A quorum queue's **replica set is fixed at declaration** and does
  **not** auto-grow when a node joins later (RabbitMQ 3.9 has no
  Continuous Membership Reconciliation). So the queues must be
  (re)declared while **both** controllers are already in the cluster —
  declaring them on `controller1` before C3 would leave them
  single-replica and not actually HA.

Hence this lands *after* C3 (cluster formed), never before: enable
quorum with all clients stopped and rabbit purged, so every queue is
recreated as quorum with a replica on each node.

1. **Merge a one-line data-bag change** adding the flag (this is the
   merge you deliberately held back from the C1 MR):

   ```jsonc
   "messaging": {
     "endpoint": ["controller1.<domain>", "controller2.<domain>"],
     "quorum_queues": true
     // ...existing keys
   }
   ```
   This flips `openstack_rabbit_quorum_queue?`
   ([libraries/helpers.rb](../libraries/helpers.rb)), which makes every
   service render `[oslo_messaging_rabbit]\nrabbit_quorum_queue = true`.
   Merging alone changes nothing until the steps below run.

2. **Stop every RabbitMQ client** so nothing recreates a classic queue
   mid-migration. On **both controllers** (`httpd` covers the mod_wsgi
   services — keystone, nova-api, nova-metadata, placement, cinder-api,
   horizon):

   ```bash
   systemctl stop httpd \
     openstack-nova-conductor openstack-nova-scheduler openstack-nova-novncproxy \
     neutron-server neutron-dhcp-agent neutron-l3-agent neutron-linuxbridge-agent \
     neutron-metadata-agent neutron-metering-agent \
     openstack-cinder-scheduler openstack-cinder-volume \
     openstack-heat-api openstack-heat-api-cfn openstack-heat-engine \
     openstack-glance-api \
     openstack-ceilometer-central openstack-ceilometer-notification
   # catch any stragglers — must come back empty before continuing:
   systemctl list-units 'openstack-*' 'neutron-*' --state=running
   ```

   And on **every hypervisor**:

   ```bash
   systemctl stop openstack-nova-compute openstack-ceilometer-compute \
     neutron-linuxbridge-agent
   # confirm nothing OpenStack is still running on the hypervisor:
   systemctl list-units 'openstack-*' 'neutron-*' --state=running
   ```

3. **Purge the existing (classic) queues** while the clients are down,
   so the redeclare can't collide. **Delete and recreate the `/` vhost**
   — this drops every queue, exchange, and binding at once, including
   *unresponsive* ones, without enumerating them. Do **not** use a
   `list_queues`/`delete_queue` loop: `list_queues` hangs with `Some
   queue(s) are unresponsive` the moment a classic queue is wedged, so
   the loop never runs. On **one** controller (it's cluster-wide):

   ```bash
   rabbitmqctl delete_vhost /
   rabbitmqctl add_vhost /
   rabbitmqctl set_permissions -p / <rabbit-user> ".*" ".*" ".*"
   rabbitmqctl list_queues -p / name | wc -l   # 0 — clean slate
   ```

   The rabbit user (`messaging.user`) survives — users are global; you
   only re-grant its permissions on the recreated vhost. If
   `delete_vhost` itself hangs on a wedged queue process, fully **stop**
   `rabbitmq-server` on **both** nodes, **start** them again, then
   re-run the three commands.

4. **Run chef on both controllers.** It renders the quorum config and
   restarts the daemons; with rabbit purged and both nodes clustered,
   every queue is declared fresh as `quorum` with a replica on each
   node. Conductor first is fine, but a full converge handles it.

5. **Start the hypervisor agents** — `openstack-nova-compute`,
   `openstack-ceilometer-compute`, `neutron-linuxbridge-agent` (stopped
   in step 2) — so they reconnect and declare their own queues as
   quorum.

6. **Verify** the queues are quorum and replicated on both nodes:

   ```bash
   # type column should read "quorum" for the RPC queues
   rabbitmqctl list_queues name type members | grep -E 'conductor|scheduler|q-'
   # members should list BOTH rabbit@controller1 and rabbit@controller2
   openstack compute service list && openstack network agent list
   ```

   If a service logs `PRECONDITION_FAILED ... inequivalent arg
   'x-queue-type'`, a classic queue of that name survived the purge —
   stop that service, `rabbitmqctl delete_queue <name>`, start it again.

`reply_*` and `*_fanout_*` queues stay transient/classic by design
(oslo doesn't make them quorum, and they can't be); only the durable
RPC/notification queues become quorum. That's expected.

---

# D. Validation & finalize

## D1 — Failover test

While there's still an attentive operator on the call:

1. On `controller1` (current MASTER):

   ```bash
   sudo systemctl stop keepalived
   ```

2. Within ~3s the VIP should appear on `controller2`:

   ```bash
   # On controller2
   ip addr show | grep <vip_v4>
   ```

3. Verify the API still answers via the VIP:

   ```bash
   openstack endpoint list
   ```

4. Bring the master back:

   ```bash
   # On controller1
   sudo systemctl start keepalived
   ```

   The VIP returns to `controller1` (priority 100 vs 90, default
   preempt).

If failover doesn't work (VIP doesn't move, or both controllers think
they're MASTER), check VRRP advertisements with `tcpdump -i <iface>
vrrp` on each node. Common causes: firewall blocking VRRP multicast,
mismatched `virtual_router_id`, mismatched `auth_pass`.

## D2 — Migrate existing neutron routers to L3 HA

`network.ha = true` (merged in C1) makes routers created **after** the
cutover HA-enabled. Existing routers stay single-agent.

**Identify which routers need migration.** `openstack router list
--long` includes an `HA` column — anything `False` was created under
the old `l3_ha = False` default and needs the flip below:

```bash
# All routers with their HA state
openstack router list --long

# Just the non-HA ones (the targets for this step)
openstack router list --long -f value -c ID -c Name -c HA \
  | awk '$NF == "False" { print }'
```

Also check routers that are *already* HA but only have one L3 agent
(if any predate `max_l3_agents_per_router = 2`):

```bash
# Router → number of L3 agents serving it
openstack router list -f value -c ID -c Name | while read id name; do
  count=$(openstack network agent list --router "$id" -f value | wc -l)
  echo "$count $id $name"
done | sort -n
```

For HA routers showing `1` agent, the scheduler will usually add the
second agent on its own once `controller2`'s L3 agent is up and
`max_l3_agents_per_router = 2` is in effect; force it with
`openstack network agent add router <agent_id> <router_id>` if
needed.

Flip every non-HA router in one pass. Neutron only lets you flip
`--ha` while the router is admin-down; the gateway, fixed IPs, and any
attached floating IPs are preserved across the flip — no need to
unset/re-attach.

```bash
# Same selector as above: every router whose HA column is False.
openstack router list --long -f value -c ID -c HA \
  | awk '$NF == "False" { print $1 }' \
  | while read -r ROUTER; do
      echo "=== flipping $ROUTER ==="
      openstack router set --disable --ha "$ROUTER" || { echo "FAILED to disable/set-ha $ROUTER"; continue; }
      openstack router set --enable "$ROUTER"       || echo "FAILED to re-enable $ROUTER"
    done
```

Then verify every router flipped and picked up two L3 agents:

```bash
openstack router list -f value -c ID -c Name | while read -r id name; do
  ha=$(openstack router show "$id" -c ha -f value)
  count=$(openstack network agent list --router "$id" -f value | wc -l)
  echo "$ha $count $id $name"
done
# Want: ha=True and count=2 for every router once
# max_l3_agents_per_router=2 + dhcp_agents_per_network=2 are in play.
```

Each flip causes a brief data-plane interruption for tenants behind
that router (the L3 agent re-creates the qrouter namespace). Looping
hits every tenant in quick succession, so run the loop inside the
maintenance window — or break it into per-tenant batches if you need
to schedule the interruptions individually.

**If `set --ha` fails on your neutron version** ("router has a
gateway", "cannot change ha on attached router", etc.), you have to
take the conservative path: detach every floating IP referencing the
router, unset the external gateway, flip `--ha`, re-attach the
gateway with `--fixed-ip subnet=<id>,ip-address=<addr>` to preserve
the public IPs, then re-attach the floating IPs. Floating IPs that
SNAT outbound from instances must keep the same address.

## D3 — Verify cinder active/active

`block-storage.cluster` was added in the A2 data-bag MR, so by this
point `cinder.conf` on both controllers renders the `cluster =
<name>` and `[coordination] backend_url = mysql://...` blocks. After
both `cinder-volume` services have restarted (which C2 / C3 take care
of), verify:

```bash
cinder-manage cluster list
# Should show one cluster row with two services bound
```

Existing volumes attach to the cluster automatically on the next
volume operation.

## D4 — Post-migration cleanup

- [ ] **Re-enable the chef-client cron** on both controllers and every
      hypervisor (paused at the top of phase C). Run one converge by
      hand first and confirm it's a no-op / no unexpected restarts.
- [ ] Remove the manual-VIP scripts / NetworkManager profiles /
      systemd units from `controller1`. They're no longer load-bearing
      and will conflict if accidentally re-enabled.
- [ ] Update Prometheus scrape targets to scrape `openstack_exporter`
      on **both** controllers as separate targets (it always binds
      `0.0.0.0`, so it can't go behind the VIP — see comment in
      [libraries/helpers.rb:218-224](../libraries/helpers.rb#L218-L224)).
- [ ] Update any external monitoring that healthchecks the API to hit
      the VIP (it should already, since the VIP IP didn't change).
- [ ] Confirm both controllers' HAProxy stats pages show all backends
      `UP` for ≥24h before considering migration complete.
- [ ] Update internal docs / wiki: there are now two controllers; ssh
      into either, but writes to `/etc/openstack` config files must go
      through chef.

---

## Rollback

**If C2 failed before C3** (i.e. `controller2` isn't joined yet):

1. **Revert the data-bag MR.** Without the `ha` block,
   `osl-openstack::ha` is skipped entirely
   ([recipes/controller.rb:23](../recipes/controller.rb#L23)). Revert
   `messaging.endpoint`, `memcached.endpoint` to single strings.
   Revert `network.ha` to absent.
2. **Manually**:
   - `systemctl stop keepalived haproxy`
   - `systemctl disable keepalived haproxy`
   - Re-add the manual VIP to `<vrrp-iface>`.
   - Edit Apache vhosts back to `Listen *:<port>` (or run chef, which
     will, since `openstack_api_listen_ip` returns `'*'` when `ha` is
     absent).
   - Restart httpd + the native API daemons.
3. Run chef once on `controller1` to converge the rolled-back state.

After C3, rolling back is harder because `controller2` has joined the
rabbit cluster and is actively serving traffic. The supported path at
that point is forward — fix the issue rather than tear it down.

## Known Gotchas

- **VIP duplicate-bind on first run.** If you forget to drain the
  manual VIP before chef runs (C2 step 1), keepalived will start
  alongside the manual assignment and the address will be present
  twice. Fix: `ip addr del <vip>/<mask> dev <iface>`, then
  `systemctl restart keepalived`.
- **HAProxy package default `bind *:5000`.** The package ships a demo
  frontend that grabs port 5000 wildcard. The recipe overwrites the
  config and runs `execute[haproxy_release_wildcards]` to restart
  haproxy, but if the package install starts the service before the
  overwrite, Apache's keystone vhost will fail to bind. The recipe
  handles this; if you see Apache start failures complaining about
  port 5000, check that
  [recipes/ha.rb:86-114](../recipes/ha.rb#L86-L114) ran.
- **Native daemons holding wildcard.** glance-api, neutron-server,
  heat-api, heat-api-cfn, nova-novncproxy historically bind
  `0.0.0.0:port`. The recipe restarts them so they pick up
  `bind_host = <api_listen_ip>` before HAProxy tries to bind the VIP
  on the same port. The `service[haproxy_post_daemons_restart]`
  delayed restart
  ([recipes/ha.rb:194-206](../recipes/ha.rb#L194-L206)) makes sure
  HAProxy comes up *after* they release the wildcard sockets.
- **RabbitMQ FQDN mismatch.** Mnesia node identity is the full Erlang
  node name (`rabbit@<fqdn>`). If `controller2`'s hostname comes up
  as `controller2.novalocal` instead of `controller2.<your-domain>`,
  the join silently fails or creates a phantom node. The
  `osl_openstack_messaging` resource forces `USE_LONGNAME=true` and
  pins `NODENAME` to the FQDN form, but DNS / `/etc/hosts` must
  agree.
- **Erlang dist + EPMD ports.** Cluster traffic uses 4369 (EPMD) and
  25672 (Erlang dist) in addition to 5672 (AMQP) and 15672
  (management). The `rabbitmq_mgt` profile in `osl-firewall` opens
  all four. If clustering doesn't form, check iptables for those
  ports between the two controllers.
- **Don't restart both rabbit nodes simultaneously.** A coordinated
  outage of both will require `rabbitmqctl force_boot` on whichever
  node had the latest mnesia state to get the cluster back. For
  rolling restarts: stop one, wait for it to leave the cluster
  cleanly (`rabbitmqctl stop_app && rabbitmqctl reset && rabbitmqctl
  start_app && rabbitmqctl join_cluster ...`), then the other.
- **`ip_nonlocal_bind`.** HAProxy on the BACKUP controller binds the
  VIP it doesn't currently hold. The `sysctl` resources in
  [recipes/ha.rb:27-31](../recipes/ha.rb#L27-L31) set
  `net.ipv4.ip_nonlocal_bind=1` and `net.ipv6.ip_nonlocal_bind=1` —
  without these, HAProxy fails to start on the BACKUP node.
- **Kitchen suite for verification.** Before the prod cutover, run
  the `multinode` kitchen suite (uses
  [test/integration/data_bags/openstack/multinode.json](../test/integration/data_bags/openstack/multinode.json))
  to exercise the same data bag schema with two real controller VMs
  and a rabbit cluster. The `ha` suite
  ([test/integration/data_bags/openstack/ha.json](../test/integration/data_bags/openstack/ha.json))
  exercises only the `osl-openstack::ha` recipe in isolation, not
  the full controller stack.

## Recovering an inconsistent RabbitMQ cluster

Symptoms: `rabbitmqctl list_queues` returns **different totals on each
node**, or hangs with *"Some queue(s) are unresponsive"*; services log
`MessagingTimeout` even though `cluster_status` shows
`Network Partitions: (none)`. This happens when a clustered rabbit node
is **rebooted or restarted under load** — classic transient queues
(`reply_*`, `*_fanout_*`) are not replicated, so the nodes' mnesia
views diverge and don't reconverge. (Quorum queues, enabled by the `ha`
block, are the fix going forward; this runbook recovers a cluster that
got into the bad state.)

OpenStack RPC queue state is **disposable** — durable state lives in
MySQL, and transient queues do not survive a broker restart. So the
recovery is: stop every client, flush the brokers, confirm the nodes
agree, restart clients. The VIP is unaffected (keepalived is
independent of the rabbit app).

**First, pause the chef-client cron on all controllers and
hypervisors** (re-enable when done) — an automatic converge mid-recovery
will restart services and recreate queues, undoing the flush. Don't
start a step inside the :00–:10 or :30–:40 cron windows, and check
`pgrep -af chef-client` first.

1. **Stop ALL OpenStack clients** — `httpd` + every standalone daemon
   on **both controllers** (the explicit stop list is in
   [C4 step 2](#c4--enable-rabbitmq-quorum-queues)), and
   `openstack-nova-compute` + `openstack-ceilometer-compute` +
   `neutron-linuxbridge-agent` on **every hypervisor**. Confirm nothing
   is left:
   `systemctl list-units 'openstack-*' 'neutron-*' --state=running`.

2. **Flush transient queues** with a rolling broker restart (keeps the
   cluster formed). Restart the BACKUP/peer first, then the VIP holder:
   `systemctl restart rabbitmq-server` on controller2, wait for
   `cluster_status` healthy, then the same on controller1.

3. **Gate — the two nodes must now AGREE.** Run on both:
   `rabbitmqctl list_queues name | wc -l`. If the counts match and are
   small (just the durable `notifications.*` survivors), the cluster is
   consistent → go to step 5.

4. **If they still disagree** (or `list_queues` hangs on unresponsive
   queues), rebuild from a single authoritative node. With clients
   still stopped, make controller1 the clean seed:

   ```bash
   # controller2: leave the cluster
   rabbitmqctl stop_app
   # controller1: drop controller2, then flush
   rabbitmqctl forget_cluster_node rabbit@controller2.<domain>
   systemctl restart rabbitmq-server
   rabbitmqctl list_queues name        # fast now; users/perms intact
   # controller2: wipe and rejoin
   rabbitmqctl reset
   rabbitmqctl join_cluster rabbit@controller1.<domain>
   rabbitmqctl start_app
   ```
   (If `reset` hangs: `systemctl stop rabbitmq-server` on controller2,
   `rm -rf /var/lib/rabbitmq/mnesia/*`, start it, then `stop_app` /
   `join_cluster` / `start_app`.) Re-run the step-3 gate.

5. **Start OpenStack back** — controllers first (conductor first, then
   the other daemons, the neutron/ceilometer agents, then `httpd`),
   then the hypervisors. Confirm the `conductor` queue shows the same
   consumer count from both nodes, then `openstack compute service
   list` / `network agent list` / `server list`.

Do not skip step 1: a broker flush with clients still connected just
re-creates the inconsistent transient queues. And until the quorum-queue
config is deployed everywhere, **don't reboot a controller** without
draining clients first.
