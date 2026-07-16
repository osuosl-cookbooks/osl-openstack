# Design: shared 3-node RabbitMQ messaging tier

Status: implemented in the cookbook and validated in the multi-node test
env (3-node EL10 tier, TLS-only, CMR, quorum queues verified). See
[Production deployment](#production-deployment-bringing-the-tier-online)
for the build-out steps.

## Motivation

Quorum queues are Raft-based and need a **majority** of members to
accept writes (`(N/2)+1`). On a **2-node** controller cluster a quorum
queue has 2 members, so the majority is 2 — losing either controller
drops below quorum and **publishes are NACKed**
(`amqp.exceptions.MessageNacked` → `MessageDeliveryFailure`). This was
confirmed on the multi-node test env: shutting down `controller2` left
`compute` unable to publish to `conductor`, and nova marked it `down`.
A 2-member quorum queue tolerates **zero** failures.

Quorum only delivers fault tolerance on an **odd** cluster (3 tolerates
1, 5 tolerates 2). Rather than add a 3rd rabbit node to each of the
three OpenStack clouds (9 nodes, three clusters to manage), run **one
shared 3-node RabbitMQ cluster** that serves all three clouds, isolated
per-cloud by vhost.

## Target topology

```
            ┌─────────────── messaging tier (same site) ───────────────┐
            │   mq1 ── mq2 ── mq3   (one cluster, quorum)               │
            │     vhosts:  x86      arm      ppc64                     │
            └────▲───────────────▲───────────────▲─────────────────────┘
                 │ amqps 5671     │               │
        ┌────────┴───────┐ ┌──────┴────────┐ ┌────┴───────────┐
        │ cloud-a        │ │ cloud-b       │ │ cloud-c        │
        │ ctrl1/ctrl2 +  │ │ ctrl1/ctrl2 + │ │ ctrl1/ctrl2 +  │
        │ hypervisors    │ │ hypervisors   │ │ hypervisors    │
        └────────────────┘ └───────────────┘ └────────────────┘
```

- **3 dedicated RabbitMQ VMs** cluster *among themselves* (shared Erlang
  cookie; epmd 4369 + dist 25672 between the 3 only). Spread them across
  separate hypervisors/failure domains.
- **Metadata store: Khepri** (the default in 4.2). Cluster metadata
  (vhosts, users, queues, bindings) is managed by Raft, so it stays
  consistent across the 3 nodes — **no `cluster_partition_handling`
  tuning** (that setting is unused under Khepri and removed in 4.3;
  partition behavior is Raft's, non-configurable). Bonus: the mnesia
  metadata-divergence that caused the original incident (`list_queues`
  disagreeing per node) **cannot happen** under Khepri. Metadata writes
  stay available with 1 node down (2/3 majority).
- **Controllers no longer run RabbitMQ.** Each cloud's controllers and
  hypervisors are plain AMQP clients to all 3 tier nodes.
- **vhost-per-cloud isolation is mandatory.** Every cloud declares
  queues literally named `conductor`, `scheduler`, etc.; one shared
  vhost would collide them. Each cloud gets its own vhost + user with
  permissions scoped to that vhost only.
- Quorum queues are declared per-vhost across the 3 nodes → **3 replicas,
  tolerate 1 node down** — the failover case that fails on 2 nodes.

## Configuration / data-bag changes

### New: messaging-tier data bag + role

The 3 tier nodes reuse the existing `osl_openstack_messaging` building
blocks (cookie sync, longname nodename, `join_cluster`) but on their own
nodes. Tier data bag carries:
- `nodes` / `primary_node` (e.g. `rabbit@mq1.<domain>`), `cookie`
- a list of clouds to provision: `{ vhost, user, pass }` per cloud

### Each cloud's `openstack` data bag (the `messaging` block)

| key | today (embedded) | shared tier |
|-----|------------------|-------------|
| `endpoint` | `[ctrl1, ctrl2]` | `[mq1, mq2, mq3]` |
| `vhost` | _(implicit `/`)_ | `x86` (bare name, no leading slash) **(new key)** |
| `user` / `pass` | shared `openstack` | per-cloud creds |
| `cookie`, `primary_node` | set | **removed** (clients don't cluster) |
| `quorum_queues` | _(unset)_ | `true` |

Run-list change: **remove `recipe[osl-openstack::ops_messaging]`** from
the controllers — they no longer host a broker.

## Cookbook changes

1. **`openstack_transport_url` gains a vhost.** Today it hardcodes the
   trailing `/` ([libraries/helpers.rb:192](../libraries/helpers.rb#L192)
   → `rabbit://…:5672/`). Read `messaging.vhost` (default `/` for
   back-compat) so it renders
   `rabbit://user:pass@mq1:5671,mq2:5671,mq3:5671/x86` — the port 5671 +
   `ssl=true` come from the `messaging.tls` flag (see Security &
   monitoring). Use bare vhost names (`x86`, not `/x86`) so the URL path
   is clean and needs no `%2F` encoding.
2. **Tier provisioning.** A recipe/role that installs + clusters the 3
   nodes (needs the EL10 / RabbitMQ-4 repo change — item 7),
   enables CMR (target group size 3), and creates the per-cloud
   **vhosts + users** with vhost-scoped permissions
   (`set_permissions -p x86 ...`). This extends the per-user/permission
   logic in [resources/messaging.rb](../resources/messaging.rb) to be
   vhost-aware and loop over the cloud list; the cookie/longname/
   `join_cluster` logic is reused as-is. (No partition-handling config —
   Khepri, see Target topology.)
3. **Controllers skip the broker** — don't include `ops_messaging`; the
   `osl_openstack_messaging` resource no longer runs on them.
4. **Firewall**: the tier needs **5671** (TLS AMQP) from each cloud's
   controllers + hypervisors (5672 too during migration, closed after),
   **15692** from Prometheus, and 4369/25672 among the tier nodes. The
   `rabbitmq_mgt` named port (in **osl-firewall**) currently covers
   4369/25672/5672/15672 — extend it to add **5671** and **15692**.
5. The `messaging.quorum_queues` flag + templates from
   `ramereth/rabbitmq-quorum-queues` are unchanged — they finally run
   against a cluster where quorum is meaningful.
6. **Update the multi-node test env to this topology.** It currently
   deploys embedded 2-node RabbitMQ on the controllers — the exact
   setup that just *failed* the failover test. Add 3 `mq` nodes
   (`mq1`/`mq2`/`mq3`) running the tier role, drop `ops_messaging` from
   the controller run-lists, and point
   [test/integration/data_bags/openstack/multinode.json](../test/integration/data_bags/openstack/multinode.json)
   at `[mq1, mq2, mq3]` with a `vhost` + `quorum_queues: true` (and move
   `cookie`/`primary_node` to the tier's data bag). Then re-run the
   failover test (reboot one `mq` node) — it should now **pass** (quorum
   holds 2 of 3), validating the production topology in CI before any
   real cloud cuts over. This is also the rig to develop the
   `messaging.vhost` helper and tier-provisioning recipe against.
   **Status: done** — `main.tf` deploys mq1/mq2/mq3 (EL10, converged
   before the controllers), the controllers no longer run
   `ops_messaging`, and inspec asserts the 3-node cluster, CMR, TLS-only
   listener, and a real quorum queue in the cloud vhost.
7. **RabbitMQ 4.2 repo support — DONE.** `openstack_rabbitmq_repo`
   ([libraries/helpers.rb:52-64](../libraries/helpers.rb#L52)) now has a
   `when 10` arm pointing at the SIG **`rabbitmq-4`** subdir (4.x).
   Verified against the live mirror: EL10 ships **only** `rabbitmq-4`,
   EL9 has both `rabbitmq-4` and `rabbitmq-38`; the cookbook keeps
   EL8/EL9 on `rabbitmq-38`/3.9. GPG key unchanged — the CentOS SIG
   Messaging key in `resources/messaging.rb` signs `rabbitmq-4` too.
   Remaining: an EL10 test platform to exercise it in CI (change 6).

## Production deployment: bringing the tier online

This is Phase 0 of the migration in concrete steps — build and verify
the tier once, before any cloud cuts over. Everything the broker needs
(repo, package, dir ownership, cookie, clustering, TLS, vhosts, CMR,
firewall) is handled by `osl-openstack::ops_messaging`; the manual work
is VMs, DNS, a data bag, a role, and converge order.

### 1. Provision the VMs

Three identical Ganeti VMs per [VM specs](#vm-specs): **AlmaLinux 10**,
8 vCPU / 16 GB / 60-100 GB **plain (local) SSD** disk — no DRBD — and
**one per physical host** (anti-affinity is load-bearing; see VM specs).
Add DNS A records for `mq1`/`mq2`/`mq3.bak.osuosl.org`. The standard
wildcard cert does not cover this domain, so the tier needs a
`*.bak.osuosl.org` cert in its own `certificates` bag item, selected via
`messaging.ssl_search_id` (step 2).

### 2. Create the tier data bag item

The mq nodes read their own encrypted `openstack` bag item — they are
not part of any cloud's item. Generate the Erlang cookie and per-cloud
passwords (`openssl rand -hex 20` each):

```json
{
  "id": "messaging_tier",
  "messaging": {
    "user": "openstack",
    "pass": "<admin pass>",
    "cookie": "<cookie>",
    "primary_node": "rabbit@mq1.bak.osuosl.org",
    "tls": true,
    "tls_only": true,
    "ssl_search_id": "wildcard-bak",
    "cmr_target_group_size": 3,
    "vhosts": [
      { "vhost": "arm",   "user": "arm",   "pass": "<arm pass>" },
      { "vhost": "ppc64", "user": "ppc64", "pass": "<ppc64 pass>" },
      { "vhost": "x86",   "user": "x86",   "pass": "<x86 pass>" }
    ]
  }
}
```

`tls_only: true` from day one: no cloud ever speaks plaintext to the
tier (each arrives with `messaging.tls` at its cutover), so 5672 never
needs to be offered. `ssl_search_id` names the `certificates` bag item
holding the `*.bak.osuosl.org` cert (`wildcard-bak` here; defaults to
`wildcard` when unset).

### 3. Create the role

`roles/openstack_messaging.json`, mirroring how the per-cloud roles
select their bag item:

```json
{
  "name": "openstack_messaging",
  "description": "Shared RabbitMQ messaging tier node",
  "json_class": "Chef::Role",
  "chef_type": "role",
  "run_list": [
    "recipe[osl-openstack::ops_messaging]",
    "recipe[osl-openstack::mon]"
  ],
  "default_attributes": {
    "osl-openstack": {
      "databag_item": "messaging_tier",
      "node_type": "messaging"
    }
  }
}
```

Requires the osl-firewall release with 5671/15692 in `rabbitmq_mgt`
(already merged) — the resource opens all tier ports itself, OSL-only.

### 4. Bootstrap, then converge in order: mq1 first

Bootstrap all three nodes with the normal method (no role), then add
the role and converge **one node at a time, mq1 (the primary) first** —
it starts the broker, writes the TLS config, and creates the three
vhosts/users. mq2 and mq3 join mq1 (`join_cluster`) and receive the
vhosts/users via Khepri replication.

```
# per node, mq1 first:
knife node edit mq1.bak.osuosl.org   # add role[openstack_messaging] to the run list
ssh mq1.bak.osuosl.org cinc-client
# verify (step 5 subset), then repeat for mq2, then mq3
```

### 5. Verify the tier

```
# on each mq node
rabbitmqctl cluster_status              # 3 running nodes, khepri store
rabbitmqctl -t 60 await_online_nodes 3
rabbitmqctl -q list_vhosts              # arm / ppc64 / x86 on ALL nodes
ss -tlnp | grep -E ':(5671|5672)'       # 5671 listening, 5672 absent

# from a controller of each cloud (reachability + cert)
openssl s_client -connect mq1.bak.osuosl.org:5671 -brief </dev/null
```

`list_vhosts` succeeding on mq2/mq3 doubles as the replication check —
the vhosts only exist there via Khepri.

### 6. Monitoring — before the first cutover

Chef handles the node side: the management + prometheus plugins are
enabled by default (`messaging.plugins` overrides), the mon recipe
(via `node_type: messaging`) installs the NRPE checks from
[Security & monitoring](#security--monitoring), and the Prometheus
server scrapes the tier via the `rabbitmq` job in
`osl-prometheus::server`. Remaining manual work: the Nagios server
service definitions for the new checks, the alert rules, and the
3-VMs-on-3-distinct-Ganeti-hosts check. Paging on quorum loss is the
blast-radius mitigation — it must exist before a cloud depends on the
tier.

### 7. Failover validation

While nothing depends on the tier yet, reboot one mq node: the other
two must keep serving (`await_online_nodes 2` succeeds), and the
rebooted node must rejoin to 3. This is the exact failure the tier
exists to survive — cheapest to prove now.

Then start the per-cloud cutovers below, in the decided order
`arm → ppc64 → x86`.

## Migration (per cloud, one at a time)

Stand up the tier first
([Production deployment](#production-deployment-bringing-the-tier-online)),
then cut each cloud over in its own window.

**One-time pre-work (before the first cloud):** `ops_messaging` sits in
the shared `openstack_controller` role, so it can't be dropped per
cloud. Detach it once — pin it onto every controller node, then remove
it from the role:

```bash
for n in $(knife search node 'roles:openstack_controller' -i 2>/dev/null \
    | awk 'NF && !/items found/'); do
  knife node run_list add "$n" 'recipe[osl-openstack::ops_messaging]'
done
# then delete it from roles/openstack_controller.json and upload the role
```

**Phase N — cut over one cloud** (from the jumphost with dsh; `arm`
shown). RPC/notifications are disposable (durable state is in MySQL),
but the control plane is *down* from step 3 to step 6 — quiesce
long-running async work first (no in-flight live migrations, volume
create/migrate, or snapshots) and announce the API outage window.

1. Build the dsh groups from chef:

   ```bash
   CLOUD=arm
   mkdir -p ~/.dsh/group
   knife search node "roles:openstack_${CLOUD} AND roles:openstack_controller" -i 2>/dev/null \
     | awk 'NF && !/items found/' > ~/.dsh/group/${CLOUD}-controllers
   knife search node "roles:openstack_${CLOUD} AND roles:openstack_compute" -i 2>/dev/null \
     | awk 'NF && !/items found/' > ~/.dsh/group/${CLOUD}-hypervisors
   cat ~/.dsh/group/${CLOUD}-controllers ~/.dsh/group/${CLOUD}-hypervisors \
     > ~/.dsh/group/${CLOUD}-all
   wc -l ~/.dsh/group/${CLOUD}-*   # 2 controllers + expected hypervisor count
   ```

2. Pause the chef-client cron everywhere (don't start inside the
   :00–:10 / :30–:40 cron windows) and confirm no run is in flight:

   ```bash
   dsh -M -c -g ${CLOUD}-all -- 'rm -f /etc/cron.d/chef-client'
   dsh -M -c -g ${CLOUD}-all -- 'pgrep -af "chef-client|cinc-client" || true'  # must be empty
   ```

3. Stop every RabbitMQ client (the
   [C4 stop list](HA_MIGRATION.md#c4--enable-rabbitmq-quorum-queues)):

   ```bash
   dsh -M -c -g ${CLOUD}-controllers -- 'systemctl stop httpd \
     openstack-nova-conductor openstack-nova-scheduler openstack-nova-novncproxy \
     neutron-server neutron-dhcp-agent neutron-l3-agent neutron-linuxbridge-agent \
     neutron-metadata-agent neutron-metering-agent \
     openstack-cinder-scheduler openstack-cinder-volume \
     openstack-heat-api openstack-heat-api-cfn openstack-heat-engine \
     openstack-glance-api \
     openstack-ceilometer-central openstack-ceilometer-notification'

   dsh -M -c -g ${CLOUD}-hypervisors -- 'systemctl stop \
     openstack-nova-compute openstack-ceilometer-compute neutron-linuxbridge-agent'
   ```

   Verify — both must come back empty (`neutron-server` workers
   sometimes hold their sockets; `kill -9` leftovers and re-check):

   ```bash
   dsh -M -c -g ${CLOUD}-all -- \
     'systemctl list-units "openstack-*" "neutron-*" --state=running --no-legend'
   dsh -M -c -g ${CLOUD}-controllers -- \
     'ss -tlnp | grep -E ":(9696|8774|8776|9292|8004|8000)" || true'
   ```

4. Merge the cloud's data-bag change (endpoint → the tier, add `vhost`
   + per-cloud creds, `tls: true`, `quorum_queues: true`, drop
   `cookie`/`primary_node`) and drop the embedded broker from this
   cloud's controllers:

   ```bash
   knife data bag edit openstack ${CLOUD}
   knife node run_list remove <controller1-fqdn> 'recipe[osl-openstack::ops_messaging]'
   knife node run_list remove <controller2-fqdn> 'recipe[osl-openstack::ops_messaging]'
   ```

5. Converge — controllers one at a time, then the hypervisors fanned
   out. Services connect to the tier and declare quorum queues in the
   fresh vhost (no purge dance — nothing to collide with). These runs
   also rewrite `/etc/cron.d/chef-client`, undoing step 2:

   ```bash
   dsh -M -g ${CLOUD}-controllers -- 'cinc-client'           # no -c: serial
   dsh -M -c -F 10 -g ${CLOUD}-hypervisors -- 'cinc-client'  # -F caps fanout
   ```

6. **Repoint nova's cell1 at the tier.** Nova stores a per-cell
   `transport_url` in the `nova_api` DB (set once by `create_cell`,
   never updated by chef) and nova-api/conductor/scheduler use *that*
   for cell RPC — not nova.conf. Skipping this leaves them dialing the
   old broker (ECONNREFUSED loops) with perfectly clean config files.
   On one controller (its nova.conf already has the tier URL;
   `update_cell` reads unspecified values from config):

   ```bash
   nova-manage cell_v2 list_cells --verbose   # cell1 shows the OLD url
   nova-manage cell_v2 update_cell --cell_uuid <cell1-uuid>
   nova-manage cell_v2 list_cells --verbose   # now the tier url
   dsh -M -g ${CLOUD}-controllers -- \
     'systemctl restart httpd openstack-nova-conductor openstack-nova-scheduler openstack-nova-novncproxy'
   ```

7. Verify the cloud is on the tier, then `openstack server list` /
   boot a test instance:

   ```bash
   ssh mq1.bak.osuosl.org \
     "rabbitmqctl -q list_queues -p ${CLOUD} name type members | head"
                             # type=quorum, members list all 3 mq nodes
   dsh -M -c -g ${CLOUD}-all -- 'ls /etc/cron.d/chef-client'  # cron restored
   ```

8. **Stop the now-unused embedded broker, soak, then decommission.**
   The C4 stop list doesn't touch `rabbitmq-server`, and with
   `ops_messaging` off the run list nothing manages it — stop it
   explicitly:

   ```bash
   dsh -M -c -g ${CLOUD}-controllers -- 'systemctl disable --now rabbitmq-server'
   ```

   It stays *installed but stopped* through the soak (e.g. a few days
   stable) — that's what keeps the rollback below possible. Only after
   the soak, remove the package/data.

**Rollback (per cloud).** The window from step 3 to a healthy step 7 is
an API outage; if the tier is unreachable, a vhost/cred is wrong, or
quorum won't form, revert:
1. Restore the data bag (`knife data bag edit openstack ${CLOUD}`):
   `messaging.endpoint` → the two controllers, re-add
   `cookie`/`primary_node`, drop `vhost`/`tls`/`quorum_queues`. Re-add
   the broker to both controllers:
   `knife node run_list add <fqdn> 'recipe[osl-openstack::ops_messaging]'`.
2. Start the still-installed embedded `rabbitmq-server` on both
   controllers (classic queues — no purge needed).
3. Reconverge the controllers (serial `dsh` as in step 5), rerun
   `cinc-client` on the hypervisors, and rerun step 6's `update_cell`
   (cell1 must point back at the embedded broker) + nova restarts.
   Confirm `openstack server list`.
Don't run step 8's removal until the soak passes — that's what makes
this rollback available.

Because each cloud lands in a fresh, empty vhost, the classic→quorum
purge from [C4](HA_MIGRATION.md#c4--enable-rabbitmq-quorum-queues) is
*not* needed per cloud — that complexity goes away.

**Failover validation (the test that failed on 2 nodes):** reboot one
tier node → quorum holds (2 of 3) → all clouds keep RPC.

## Operational considerations

- **Blast radius (the main trade-off).** A messaging incident now hits
  all three clouds at once instead of one. Mitigations: 3-node quorum +
  Khepri (Raft metadata, no split-brain / no mnesia divergence) is far
  more robust than the 2-node classic setup; dedicated
  monitoring/alerting; capacity headroom. Accept this consciously — it's
  the cost of centralizing.
- **Sizing.** One cluster carries the aggregate RPC + notification load
  of three clouds — control-plane traffic (small, short-lived messages),
  so sizing is driven by connection count and quorum fsync latency, not
  bandwidth. Concrete specs in [VM specs](#vm-specs); monitor queue
  depth, memory/disk alarms, file descriptors, connection count.
- **Upgrade coupling.** One RabbitMQ version for all clouds; upgrades are
  a shared maintenance event.
- **Membership on node replacement.** Queues declared with all 3 nodes
  present get 3 members. A node that fails and rejoins under the **same**
  name recovers via Raft (no action). For a **new replacement** node
  (different name) or a permanent removal, membership must change: enable
  CMR (target group size 3) on the RabbitMQ **4.2** tier so it grows the
  queues onto the new member automatically instead of a manual
  `rabbitmq-queues grow`. (One of the reasons the tier runs newer than
  the clouds' 3.9; see "RabbitMQ version & OS compatibility".)
- **TLS, monitoring, secrets** — decided; see
  [Security & monitoring](#security--monitoring) below.

## Security & monitoring

### TLS (decided: yes — TLS on 5671, wildcard cert)

Per-cloud AMQP creds now cross the network to a shared tier, so
client↔broker traffic is TLS. One wildcard cert serves all three nodes;
`messaging.ssl_search_id` names the `certificates` bag item holding it
(default `wildcard`). Production runs the tier under `bak.osuosl.org`,
which the standard wildcard does **not** cover, so it uses its own
`*.bak.osuosl.org` cert item (see
[Production deployment](#production-deployment-bringing-the-tier-online)).

- **Broker:** RabbitMQ TLS listener on **5671** (AMQPS) via
  `rabbitmq.conf` `ssl_options` — certfile/keyfile from the wildcard
  cert, `cacertfile` = its chain, `ssl_options.verify = verify_none` +
  `fail_if_no_peer_cert = false` (server-auth only; clients present no
  client cert). Inter-node 25672 / Khepri-Raft traffic stays on the
  trusted same-site network; inter-node TLS is optional, addable later.
- **Clients:** each cloud's `[oslo_messaging_rabbit]` gets `ssl = true`
  and `ssl_ca_file = <chain>` (to verify the wildcard cert), and the
  endpoint port is **5671** — the `openstack_transport_url` helper
  switches the port when a new `messaging.tls` flag is set (folds into
  the vhost change, cookbook change 1).
- **Migration:** every cloud connects over TLS from its cutover, so the
  tier runs `tls_only` (`listeners.tcp = none`) from day one — 5672 is
  never offered.

### Monitoring (Nagios + Prometheus)

- **Prometheus:** RabbitMQ 4.2 ships the built-in `rabbitmq_prometheus`
  plugin (chef-enabled by default); the `rabbitmq` scrape job in
  `osl-prometheus::server` reads `/metrics` on **15692** of all 3 nodes
  (+ node_exporter for disk / fsync latency). Alert on: memory/disk-free alarms
  (`rabbitmq_alarms_*`); cluster size < 3 nodes; **any quorum queue
  without an online majority / no leader** (the failure this design
  exists to survive); queue depth not draining
  (`rabbitmq_queue_messages_ready`); FDs near limit; connection-count
  spikes; publish-confirm latency (fsync proxy).
- **Nagios (NRPE, chef-managed):** `osl-openstack::mon` on `node_type`
  `messaging` installs per-node checks — `check_rabbitmq_running`,
  `check_rabbitmq_alarms`, `check_rabbitmq_cluster` (expect 3 running
  members, from `cmr_target_group_size`), and `check_rabbitmq_listener`
  (5671). Page on node down, alarm set, or < 3 members.
- This is the concrete form of the blast-radius mitigation: since one
  incident hits all three clouds, the quorum-loss and alarm checks must
  **page**, not just dashboard.

### Secrets & rotation (encrypted data bag)

Store the tier **Erlang cookie** and **per-cloud AMQP passwords** in an
encrypted data bag (`Chef::EncryptedDataBagItem`, same mechanism as the
cert bag). The cookie is tier-wide root-equivalent (it authenticates
cluster membership); per-cloud passwords are scoped to one vhost.

- **Rotate a per-cloud password (routine).** RabbitMQ has no
  two-passwords-per-user, so either:
  - *brief-reconnect:* update the bag → `rabbitmqctl change_password
    <user> <new>` on the tier → converge that cloud + restart its
    OpenStack services to reconnect (a short RPC blip); **or**
  - *zero-downtime:* create a second user `<cloud>-v2` with the new
    password + same vhost perms → repoint that cloud to `-v2` + restart
    its services → delete the old user. No blip.
- **Rotate the Erlang cookie (rare — e.g. on compromise).** All members
  must share the cookie simultaneously (a node with the new cookie can't
  talk to nodes with the old), so it's a coordinated **full-tier
  restart**: stop rabbit on all 3 → update the cookie (bag → converge
  writes `/var/lib/rabbitmq/.erlang.cookie`) → start all 3. Clients don't
  use the cookie, so they only see the brief broker outage. Schedule it.

## RabbitMQ version & OS compatibility

The clients (Yoga `oslo.messaging` on AlmaLinux 8/9 controllers +
hypervisors) are plain **AMQP 0-9-1** clients and do **not** cluster with
the broker — there is no Erlang/cookie/OS coupling between a client and
the tier. AMQP 0-9-1 is stable across RabbitMQ versions, so AlmaLinux 8/9
clients talk to a newer broker on AlmaLinux 10 with no issue. **The
compatibility axis is the RabbitMQ *version*, not the host OS.**

The CentOS Messaging SIG selects the RabbitMQ version by **subdir**
(`rabbitmq-38` → 3.9.x, `rabbitmq-4` → 4.x), available on both EL9 and
EL10 — **not** by host OS. The cookbook's `openstack_rabbitmq_repo`
currently hardcodes `rabbitmq-38` and has no EL10 arm, so getting 4.2
**requires a repo/helper change** (cookbook change item 7), not just a
newer host. Run the tier on **RabbitMQ 4.2 on AlmaLinux 10** (EL10 is
the new OS; 3.13 is near-EOL and not the SIG's 4.x line):
- Current, supported release with **Continuous Membership Reconciliation
  (CMR)** — when you add a genuinely *new* member node (or change a
  quorum-queue policy / target group size), CMR grows the queues onto it
  automatically, instead of a manual `rabbitmq-queues grow`. (A node
  that fails and rejoins under the *same* name is Raft recovery, not
  CMR — CMR is triggered by membership *changes*, not failures.)
- Works with Yoga oslo out of the box: oslo's transient `reply_*` /
  `*_fanout_*` queues (non-durable classic) are **deprecated but
  permitted by default through 4.2** — declaration still succeeds, just
  a cosmetic warning in the log/UI. (Exclusive non-durable queues are
  exempt from the deprecation entirely; the non-exclusive ones are the
  permitted-now / denied-at-4.3 category.)

**Upgrade gate — do not take the tier to a Mnesia-removal 4.x release
until the OpenStack clients are on a newer oslo.** The transient-queue
default flips to *denied* at **4.3.0**, but is re-permittable with
`deprecated_features.permit.transient_nonexcl_queues = true`; the true
removal comes later in 4.x with Mnesia (Khepri-only). Newer oslo
declares quorum/durable transient queues and sidesteps this. Classic
queue *mirroring* (removed in 4.0) is not used — quorum replaces it.

## VM specs

Three **identical** nodes (Raft prefers homogeneous members). Start
here and let RabbitMQ's memory/disk alarms + connection/queue-depth
metrics tell you if more is needed — control-plane load is modest.

| Resource | Recommended | Minimum | Why |
|---|---|---|---|
| vCPU | **8** | 4 | Erlang scales across cores; quorum (Raft) is more CPU-heavy than classic; three clouds' connections/channels. |
| RAM | **16 GB** | 8 GB | Driven by connections/channels (thousands × ~100–400 KB) + per-queue Raft overhead, not message backlog (OpenStack drains fast). `vm_memory_high_watermark` 0.4 → ~6.4 GB usable at 16 GB; headroom matters because an incident here hits all three clouds. |
| Disk | **60–100 GB, SSD/NVMe** | 50 GB SSD | Capacity need is small, but quorum queues **fsync every publish** — slow disk = high publish latency = every cloud feels sluggish. Fast disk is the #1 requirement. |
| Network | low-latency, same site | — | Raft chatter between nodes + client reachability. |

The cookbook already raises `LimitNOFILE` to 300000
([resources/messaging.rb:69-77](../resources/messaging.rb#L69)), which
covers a high connection count.

**Ganeti disk backing — don't double-replicate.** Quorum queues already
replicate every message across the 3 nodes at the app layer. Backing the
VMs with Ganeti **DRBD** stacks a second synchronous replication under
each quorum fsync, doubling write latency for no added safety. Use
**`plain` (local), SSD-backed** disk for these VMs:
- Quorum provides the 3 copies; DRBD's copy is redundant.
- If a Ganeti host dies, that one node is lost — quorum tolerates 1 loss
  (2 of 3). Rebuild the VM under the **same** node name and it recovers
  via Raft; only a *new*-named replacement needs CMR/grow. That's the
  failure model quorum is built for.
- Avoids the DRBD write-latency penalty on every publish.

**Anti-affinity is load-bearing, so enforce it — don't just document
it.** With plain local disk and quorum's 2-of-3 majority, two `mq` VMs
landing on the same Ganeti host means a single host failure = quorum
loss for **all three clouds**. Ganeti has no default hard anti-affinity
and `gnt-instance migrate`/failover can co-locate members. Pin it: use
exclusive primary nodes (or an anti-affinity / exclusion group), confirm
≥3 eligible physical hosts, and add a monitoring check that the 3 VMs
remain on 3 distinct hosts after any migration.

## Decisions

1. **Clouds → vhosts:** clouds `x86`, `arm`, `ppc64` → vhosts named
   `x86`, `arm`, `ppc64` (bare names, no leading slash → clean
   `rabbit://…/x86` URLs), each with its own user + vhost-scoped
   permissions.
2. **Placement:** 3 RabbitMQ VMs on the Ganeti cluster, **one per
   physical machine** (separate failure domains).
3. **Version:** RabbitMQ **4.2** (SIG `rabbitmq-4` subdir) on AlmaLinux
   10. This requires the repo-helper change (cookbook change 7) — it is
   *not* a free consequence of the host OS. Mind the 4.3 / Mnesia-removal
   upgrade gate.
4. **memcached:** out of scope for this work.
5. **Migration order:** `arm` → `ppc64` → `x86` (confirmed for prod).
   Trade-off to manage: whichever cloud goes last sits on the fragile
   embedded 2-node broker the longest, so keep the gaps between cutovers
   short.
6. **TLS:** yes — TLS on **5671**, cert selected by
   `messaging.ssl_search_id` (prod: `*.bak.osuosl.org`); plaintext 5672
   never offered (`tls_only`). See
   [Security & monitoring](#security--monitoring).
7. **Monitoring:** Nagios (NRPE `rabbitmq-diagnostics` checks) +
   Prometheus (`rabbitmq_prometheus` on 15692), paging on quorum loss /
   alarms / < 3 nodes. See [Security & monitoring](#security--monitoring).
8. **Secrets:** encrypted data bag for the Erlang cookie + per-cloud
   passwords, with the rotation procedures in
   [Security & monitoring](#security--monitoring).

## Open items before build

All done: EL10 is in the test matrix (the `messaging_tier` kitchen suite
and the multi-node terraform env), osl-firewall ships 5671/15692 in
`rabbitmq_mgt`, and the tier code (changes 1-3, 6) is implemented and
verified in the multi-node env. Production build-out steps:
[Production deployment](#production-deployment-bringing-the-tier-online).
