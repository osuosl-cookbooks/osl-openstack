# Production HA Migration Runbook

Steps to convert the existing single-controller production cloud to a
2-node active/active HA controller pair with minimal downtime.

This runbook assumes the cookbook is already at the
`ramereth/ha-controller` branch (or merged) and that you have read
[recipes/ha.rb](../recipes/ha.rb) and
[libraries/helpers.rb](../libraries/helpers.rb) for context.

## Target Architecture

| Component | Today | After |
| --- | --- | --- |
| Controllers | 1 active (`controller`) | 2 active/active (`controller`, `controller2`) |
| VIP | Manually-assigned IP on `controller` | keepalived-managed VIP, floats between nodes |
| API frontend | Apache binds `0.0.0.0` directly | HAProxy on VIP → Apache on per-host private IP |
| RabbitMQ | Single broker on `controller` | Mnesia cluster across both controllers |
| Memcached | Single instance on `controller` | Two instances, clients see both |
| Cinder volume | Single active | Active/active via `cluster` + tooz coordination |
| Neutron L3 | Single agent | `l3_ha = True`, `max_l3_agents_per_router = 2` |
| MariaDB | External `osl-mysql` primary | **Unchanged** (HA out of scope) |

## Prerequisites

- [ ] `controller2` host provisioned, OS installed, on the same L2 segment
      as `controller` (VRRP requires multicast).
- [ ] Forward + reverse DNS resolves for `controller2.<domain>`. Both
      controllers can resolve each other's FQDN to the **management/data**
      IP (not the VIP). RabbitMQ Mnesia is fragile if FQDNs don't agree.
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
- [ ] `chef-repo` and the latest `osl-openstack` cookbook uploaded to
      the chef server; `controller2` knows about the chef server and can
      register.
- [ ] Maintenance window scheduled. Plan for **30s–2m** of API
      unavailability during step 4 (the controller cutover).

## Phase 0 — Stage Cookbook Changes (no production impact)

1. Merge / tag the `ramereth/ha-controller` branch.
2. `berks upload` (or equivalent) to push the new cookbook + deps to the
   chef server. Do **not** run `chef-client` on `controller` yet.
3. Confirm `osl-openstack`, `osl-haproxy`, `osl-keepalived` versions on
   the chef server match what's in `Berksfile.lock`.

## Phase 1 — Update the Production Data Bag (no production impact)

The HA recipe is gated on `safe_dig(os_secrets, 'ha')` — see
[recipes/controller.rb:23](../recipes/controller.rb#L23). Until the `ha`
block exists in the data bag, nothing changes for any node that runs
chef.

Edit the `openstack` data bag for the prod cloud (your `x86`-suffixed
item, or whichever matches `database_server.suffix`). Add:

```jsonc
{
  "ha": {
    "keepalived": {
      "primary": {
        "controller.<domain>":  true,
        "controller2.<domain>": false
      },
      "interface": {
        "controller.<domain>":  "<vrrp-iface>",
        "controller2.<domain>": "<vrrp-iface>"
      },
      "priority": {
        "controller.<domain>":  100,
        "controller2.<domain>": 90
      },
      "virtual_router_id": <unique-1-255>,
      "auth_pass": "<vrrp-secret>",
      "vip_v4": "<existing-manual-vip-v4>",
      "vip_v6": "<existing-manual-vip-v6>"
    },
    "api_listen_ip": {
      "controller.<domain>":  "<controller-private-ip>",
      "controller2.<domain>": "<controller2-private-ip>"
    },
    "haproxy": {
      "stats_user": "<user>",
      "stats_pass": "<pass>"
    }
  }
}
```

In the same edit, convert these single-string fields to **arrays**
listing both controllers (the helpers accept either form — see
`openstack_transport_url` and `openstack_memcached_endpoints` in
[libraries/helpers.rb](../libraries/helpers.rb)):

```jsonc
{
  "messaging": {
    "endpoint": ["controller.<domain>", "controller2.<domain>"],
    "user":    "openstack",
    "pass":    "...",
    "cookie":       "<erlang-cookie>",
    "primary_node": "rabbit@controller.<domain>"
  },
  "memcached": {
    "endpoint": [
      "controller.<domain>:11211",
      "controller2.<domain>:11211"
    ]
  },
  "network": {
    "ha": true
    // ...existing keys
  }
}
```

Notes:

- `messaging.primary_node` is the FQDN-form Erlang node name of the
  **existing** broker. New nodes (controller2) join *this* node's
  cluster; this node never tries to join itself.
- `network.ha = true` flips
  [templates/neutron.conf.erb:14-16](../templates/neutron.conf.erb#L14-L16).
  Existing routers stay non-HA until you migrate them (Phase 7).
- Don't remove the old single-string forms — *replace* them. The old
  string form will not be valid once the keys become arrays.
- **Do not deploy yet.** Upload the data bag, but until you run
  `chef-client` somewhere, nothing changes.

## Phase 2 — Bootstrap controller2 With NO Run List Yet

1. Bootstrap `controller2` against the chef server with an **empty
   run_list** (or an OS-baseline-only role).
2. Run `chef-client` once. Confirm:
   - Node registered, OHAI sees the right `fqdn`, `ipaddress`,
     interfaces.
   - Both controllers' `/etc/hosts` (or DNS) resolve each other.
3. Pre-install RabbitMQ on `controller2` is **not** required — the
   `osl-openstack::ha` path will install everything when its run list is
   in place. This step is just for sanity.

## Phase 3 — Pre-cutover Sanity on controller (no impact)

On the existing controller:

```bash
# Snapshot current state for rollback comparison
ip addr show           > /root/pre-ha-ipaddr.txt
ss -tlnp               > /root/pre-ha-listening.txt
rabbitmqctl status     > /root/pre-ha-rabbit.txt
openstack endpoint list > /root/pre-ha-endpoints.txt
```

Confirm:

- The current "manual VIP" is configured on `<vrrp-iface>` (matches
  `ha.keepalived.interface[controller.<domain>]`).
- Apache currently binds `0.0.0.0` (or `*`) on 5000/8774/8776/etc.
  After cutover it will bind `ha.api_listen_ip[controller.<domain>]`
  on those ports, and HAProxy will own the VIP bind.
- No other VRRP group on the segment uses the chosen
  `virtual_router_id`.

## Phase 4 — Cutover controller (THE OUTAGE WINDOW)

This run installs keepalived + HAProxy, flips Apache from wildcard to
per-host IP, and restarts the native API daemons (glance-api,
neutron-server, heat-api, heat-cfn, nova-novncproxy) so they release
their `0.0.0.0:port` sockets before HAProxy tries to bind the VIP on
the same port.

**Outage:** API requests fail for ~30s–2m as Apache + the native
daemons restart and HAProxy picks up its listeners.

1. **Drain the manual VIP**. The VIP must not already be bound to the
   interface when keepalived starts (keepalived will not steal an
   address it didn't put there, and the duplicate bind will look like
   split-brain). Either:
   - Reuse the existing IP: `ip addr del <vip>/<mask> dev <vrrp-iface>`
     (immediately before the chef run), **or**
   - Tear down the systemd unit / NetworkManager profile / shell script
     that pins the VIP today.

2. **Run chef on controller**:

   ```bash
   sudo cinc-client 2>&1 | tee /root/ha-cutover.log
   ```

   Things to expect in the log (in order):
   - `osl-keepalived` installs, drops `keepalived.conf` includes for
     `openstack-ipv4` / `openstack-ipv6` / `openstack` sync_group,
     starts keepalived. The VIP appears on the wire within ~3s.
   - `osl-haproxy::install` installs the package; the recipe immediately
     overwrites the package-default `/etc/haproxy/haproxy.cfg` with a
     stub that binds only `127.0.0.1:18999` (haproxy 3.x rejects
     no-proxy configs, see commit message in
     [recipes/ha.rb:86-114](../recipes/ha.rb#L86-L114)).
   - Apache vhosts re-render with `Listen <api_listen_ip>:<port>` and
     reload.
   - `glance-api`, `neutron-server`, `heat-api`, `heat-api-cfn`,
     `nova-novncproxy` each restart and rebind to the per-host IP.
   - At end of run: HAProxy reloads with the real config (all listeners
     for the OpenStack APIs on the VIP). The
     `service[haproxy_post_daemons_restart]` resource queues a delayed
     restart that fires after the native daemons have released their
     wildcard sockets.

3. **Verify on controller**:

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

4. **Run the second chef pass** on controller. The recipe must be
   idempotent — only `service[haproxy] :reload` (if any haproxy bind set
   changed) should fire. Anything else updating means we have an
   ordering bug.

If anything in this phase fails badly, see [Rollback](#rollback) below.

## Phase 5 — Bring controller2 Online

1. Add `controller2` to the same role / run_list that `controller` uses
   (typically `role[osl-openstack-controller]` or whatever wraps
   `recipe[osl-openstack::controller]`).

2. Run chef on controller2:

   ```bash
   sudo cinc-client 2>&1 | tee /root/ha-join.log
   ```

   Watch for:
   - keepalived starts but does **not** take the VIP (priority 90 vs
     100). On the wire, controller2 sends VRRP advertisements but
     stays BACKUP.
   - RabbitMQ installs, the `osl_openstack_messaging` resource (see
     [resources/messaging.rb](../resources/messaging.rb)) writes
     `/var/lib/rabbitmq/.erlang.cookie`, sets `USE_LONGNAME=true` and
     `NODENAME=rabbit@controller2.<domain>` in `rabbitmq-env.conf`,
     restarts rabbit, then runs `rabbitmqctl join_cluster
     rabbit@controller.<domain>`. The join wipes controller2's local
     mnesia and copies schema from controller — non-disruptive to
     controller's existing connections.
   - Apache binds `controller2`'s `api_listen_ip` per-host IP.
   - HAProxy on controller2 binds the VIP listeners using
     `ip_nonlocal_bind=1` (it doesn't currently hold the VIP).

3. **Verify the cluster**:

   ```bash
   # On either node
   rabbitmqctl cluster_status
   # Should show both rabbit@controller.<domain> and rabbit@controller2.<domain>

   # On controller (HAProxy stats — both backends should be UP)
   curl -u <stats_user>:<stats_pass> http://<api_listen_ip>:9000/

   # API still works
   openstack endpoint list
   ```

## Phase 6 — Failover Test

While there's still an attentive operator on the call:

1. On controller (current MASTER):

   ```bash
   sudo systemctl stop keepalived
   ```

2. Within ~3s the VIP should appear on controller2:

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
   # On controller
   sudo systemctl start keepalived
   ```

   The VIP returns to controller (priority 100 vs 90, default preempt).

If failover doesn't work (VIP doesn't move, or both controllers think
they're MASTER), check VRRP advertisements with `tcpdump -i <iface> vrrp`
on each node. Common causes: firewall blocking VRRP multicast, mismatched
`virtual_router_id`, mismatched `auth_pass`.

## Phase 7 — Migrate Existing Neutron Routers to L3 HA

`network.ha = true` (set in Phase 1) makes routers created **after** the
cutover HA-enabled. Existing routers stay single-agent.

For each existing router that needs HA:

```bash
ROUTER=<router-id>

# Capture current external gateway
GW_NET=$(openstack router show $ROUTER -f value -c external_gateway_info \
        | jq -r '.network_id')

# Disable, flip ha=True, re-enable
openstack router unset --external-gateway $ROUTER
openstack router set --disable --ha $ROUTER
openstack router set --enable $ROUTER
openstack router set --external-gateway $GW_NET $ROUTER
```

Each flip causes a brief data-plane interruption for tenants behind that
router. Schedule per-tenant.

## Phase 8 — Cinder Active/Active

If `block-storage.cluster` is already set in the data bag, the
templates render the `cluster = <name>` and
`[coordination] backend_url = mysql://...` blocks (see
[templates/cinder.conf.erb:13-27](../templates/cinder.conf.erb#L13-L27)).
After both `cinder-volume` services are running, verify:

```bash
cinder-manage cluster list
# Should show one cluster row with two services bound
```

Existing volumes attach to the cluster automatically on the next
volume operation.

## Phase 9 — Post-Migration Cleanup

- [ ] Remove the manual-VIP scripts / NetworkManager profiles / systemd
      units from controller. They're no longer load-bearing and will
      conflict if accidentally re-enabled.
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

## Rollback

If the Phase 4 cutover fails before Phase 5 (i.e., controller2 isn't
joined yet):

1. **Remove the `ha` block from the data bag.** The recipe gate in
   [recipes/controller.rb:23](../recipes/controller.rb#L23) is
   `safe_dig(os_secrets, 'ha')`, so without it `osl-openstack::ha` is
   skipped entirely.
2. Revert `messaging.endpoint`, `memcached.endpoint` to single strings.
3. Revert `network.ha` to absent.
4. **Manually**:
   - `systemctl stop keepalived haproxy`
   - `systemctl disable keepalived haproxy`
   - Re-add the manual VIP to `<vrrp-iface>`.
   - Edit Apache vhosts back to `Listen *:<port>` (or run chef, which
     will, since `openstack_api_listen_ip` returns `'*'` when `ha` is
     absent).
   - Restart httpd + the native API daemons.
5. Run chef once to converge the rolled-back state.

After Phase 5, rolling back is harder because controller2 has joined
the rabbit cluster and is actively serving traffic. The supported path
at that point is forward — fix the issue rather than tear it down.

## Known Gotchas

- **VIP duplicate-bind on first run.** If you forget to drain the
  manual VIP before chef runs (Phase 4 step 1), keepalived will start
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
  on the same port. The
  `service[haproxy_post_daemons_restart]` delayed restart
  ([recipes/ha.rb:194-206](../recipes/ha.rb#L194-L206)) makes sure
  HAProxy comes up *after* they release the wildcard sockets.
- **RabbitMQ FQDN mismatch.** Mnesia node identity is the full Erlang
  node name (`rabbit@<fqdn>`). If `controller2`'s hostname comes up as
  `controller2.novalocal` instead of `controller2.<your-domain>`,
  the join silently fails or creates a phantom node. The
  `osl_openstack_messaging` resource forces `USE_LONGNAME=true` and
  pins `NODENAME` to the FQDN form, but DNS / `/etc/hosts` must agree.
- **Erlang dist + EPMD ports.** Cluster traffic uses 4369 (EPMD) and
  25672 (Erlang dist) in addition to 5672 (AMQP) and 15672
  (management). The `rabbitmq_mgt` profile in `osl-firewall` opens all
  four. If clustering doesn't form, check iptables for those ports
  between the two controllers.
- **Don't restart both rabbit nodes simultaneously.** A coordinated
  outage of both will require `rabbitmqctl force_boot` on whichever
  node had the latest mnesia state to get the cluster back. For
  rolling restarts: stop one, wait for it to leave the cluster cleanly
  (`rabbitmqctl stop_app && rabbitmqctl reset && rabbitmqctl
  start_app && rabbitmqctl join_cluster ...`), then the other.
- **`ip_nonlocal_bind`.** HAProxy on the BACKUP controller binds the
  VIP it doesn't currently hold. The `sysctl` resources in
  [recipes/ha.rb:27-31](../recipes/ha.rb#L27-L31) set
  `net.ipv4.ip_nonlocal_bind=1` and `net.ipv6.ip_nonlocal_bind=1` —
  without these, HAProxy fails to start on the BACKUP node.
- **Kitchen suite for verification.** Before the prod cutover, run the
  `multinode` kitchen suite (uses
  [test/integration/data_bags/openstack/multinode.json](../test/integration/data_bags/openstack/multinode.json))
  to exercise the same data bag schema with two real controller VMs
  and a rabbit cluster. The `ha` suite
  ([test/integration/data_bags/openstack/ha.json](../test/integration/data_bags/openstack/ha.json))
  exercises only the `osl-openstack::ha` recipe in isolation, not the
  full controller stack.
