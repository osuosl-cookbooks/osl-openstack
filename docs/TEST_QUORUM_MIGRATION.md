# Testing the quorum-queue migration on the multi-node env

> **Scope / supersession note.** This rehearses the *in-place 2-node*
> classic→quorum migration (HA_MIGRATION.md C4). For **production** that
> path is **superseded** by the shared 3-node tier
> ([SHARED_MESSAGING_TIER.md](SHARED_MESSAGING_TIER.md)) — 2-node quorum
> tolerates *zero* failures (see step 6), so it is not a real HA target.
> This runbook still earns its keep two ways: (1) it validates that
> quorum queues *declare* correctly, and (2) step 6 is the **negative**
> failover rehearsal that demonstrates why 3 nodes are required. The env
> itself should move to the `mq` tier (SHARED_MESSAGING_TIER change 6).

The `multi-node` terraform environment deploys two controllers
(`controller1` + `controller2`) with a clustered RabbitMQ, HAProxy/
keepalived on the VIP, and a `compute` node (plus `database`, `ceph`,
`chef_zero`) — driven by
[test/integration/data_bags/openstack/multinode.json](../test/integration/data_bags/openstack/multinode.json).
That data bag has the `ha` block but **no `messaging.quorum_queues`
flag**, so it comes up on **classic queues** — the same state production
is in today.

This runbook tests **only the classic→quorum migration** (the env is
already HA, so there's no single→HA cutover to rehearse here).

**Mechanics of this env:**
- Nodes: `controller1`, `controller2`, `compute`. Get IPs from
  `terraform output`; SSH in with your kitchen key.
- Converge a node: `sudo cinc-client` over SSH.
- The data bag lives on the chef-zero server; push edits from your
  working tree with `rake knife_upload`.
- **The working tree must be on `ramereth/rabbitmq-quorum-queues`** (or
  it merged) so `rake knife_upload` pushes the quorum-capable cookbook.

---

## 0. Confirm the starting state — classic queues

On `controller1`:
```bash
rabbitmqctl cluster_status       # both rabbit@controller1/2 running, partitions none
rabbitmqctl list_queues name type | grep -iE 'conductor|scheduler|q-' | head
# every RPC queue should read "classic" — no "quorum" rows yet
```

## 1. Enable the flag and push it to chef-zero

Edit [multinode.json](../test/integration/data_bags/openstack/multinode.json),
add the flag to the `messaging` block:
```jsonc
"messaging": {
  "endpoint": ["controller1.testing.osuosl.org", "controller2.testing.osuosl.org"],
  "quorum_queues": true,
  // ...existing keys (user, pass, cookie, primary_node)
}
```
Push it (nothing changes until you converge):
```bash
rake knife_upload
```

## 2. Stop every RabbitMQ client

On **`controller1` and `controller2`**:
```bash
systemctl stop httpd \
  openstack-nova-conductor openstack-nova-scheduler openstack-nova-novncproxy \
  neutron-server neutron-dhcp-agent neutron-l3-agent neutron-linuxbridge-agent \
  neutron-metadata-agent neutron-metering-agent \
  openstack-cinder-scheduler openstack-cinder-volume \
  openstack-heat-api openstack-heat-api-cfn openstack-heat-engine \
  openstack-glance-api \
  openstack-ceilometer-central openstack-ceilometer-notification
systemctl list-units 'openstack-*' 'neutron-*' --state=running   # must be empty
```
On **`compute`**:
```bash
systemctl stop openstack-nova-compute openstack-ceilometer-compute \
  neutron-linuxbridge-agent
systemctl list-units 'openstack-*' 'neutron-*' --state=running   # must be empty
```

## 3. Purge the classic queues

With all clients stopped, **delete and recreate the `/` vhost**. This
drops every queue, exchange, and binding at once — including
*unresponsive* ones — without enumerating them. (Don't use a
`list_queues`/`delete_queue` loop: `list_queues` hangs the moment any
classic queue is unresponsive with `Some queue(s) are unresponsive`, so
the loop never runs.) Run on **one** controller — it's cluster-wide:
```bash
rabbitmqctl delete_vhost /
rabbitmqctl add_vhost /
rabbitmqctl set_permissions -p / openstack ".*" ".*" ".*"   # re-grant the messaging user
rabbitmqctl list_queues -p / name | wc -l   # 0 — clean slate
```
The `openstack` user survives (users are global); you're only
re-granting its permissions on the recreated vhost. If `delete_vhost`
*itself* hangs on a wedged queue process, fully **stop**
`rabbitmq-server` on **both** nodes, **start** them again, then re-run
the three commands.

## 4. Converge to quorum

The cluster has both members, so queues declared now get a replica on
each node. Converge `controller1`, then `controller2`, then `compute`:
```bash
sudo cinc-client
```

## 5. Verify quorum + replication

On `controller1`:
```bash
# type = quorum; members lists BOTH rabbit@controller1 and rabbit@controller2
rabbitmqctl list_queues name type members | grep -iE 'conductor|scheduler|q-'

. /root/openrc
openstack compute service list   # nova-compute up
openstack network agent list     # agents alive
openstack server list            # the RPC call path works
```
If a service logs `PRECONDITION_FAILED ... inequivalent arg
'x-queue-type'`, a classic queue survived the purge — stop that service,
`rabbitmqctl delete_queue <name>`, start it again.

## 6. Failover test — EXPECT IT TO FAIL on this 2-node env

This is the lesson, **not a pass**. The multinode env has only **2**
RabbitMQ nodes, so each quorum queue has 2 members and a majority of 2 —
it tolerates **zero** failures. Reboot either node and it drops below
majority: publishes are NACKed and the control plane breaks. This is the
*negative rehearsal* that proves why production needs the 3-node `mq`
tier. Do **not** expect it to survive here.
```bash
# reboot one node
ssh controller2 sudo reboot

# while it's down, from controller1 — EXPECTED to fail, not pass:
rabbitmqctl cluster_status                              # controller2 absent
. /root/openrc && openstack server list                # EXPECTED to hang / error
journalctl -u openstack-nova-compute | grep -i Nacked  # the MessageNacked we expect
openstack compute service list                         # compute shows 'down'
```
You should see exactly the `MessageNacked` / `MessageDeliveryFailure`
that motivated this design. When controller2 returns, the queues regain
majority and recover.

**The PASSING failover test belongs on the 3-node tier**
([SHARED_MESSAGING_TIER.md](SHARED_MESSAGING_TIER.md), cookbook change 6):
once the env runs against `mq1`/`mq2`/`mq3`, rebooting one `mq` node
keeps quorum (2 of 3) and the API stays up. **That test cannot pass on a
2-node cluster** — which is the whole point.

## Re-running the test from scratch

A quorum queue can't be converted back to classic in place, so to
rehearse again from a clean classic-queue baseline either:
- rebuild the env (`terraform destroy` / re-apply with the flag absent), or
- revert `quorum_queues` from multinode.json, `rake knife_upload`, then
  repeat steps 2–4 (stop → purge → converge) to redeclare everything as
  classic.
