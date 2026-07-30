# Design: shared valkey coordination (tooz lock) tier

Status: tier implemented in the cookbook (`ops_coordination` on the mq
nodes); the client side (cinder pointing tooz at it) lands as a
follow-up change. Runs on the same three mq nodes as the
[shared RabbitMQ messaging tier](SHARED_MESSAGING_TIER.md).

## Motivation

Cinder volume attach failed with HTTP 500 on all three clusters. The
`attachment_update` API takes a tooz lock named
`cinder-attachment_update-<volume_uuid>-<connector_host>`, which always
exceeds 64 characters, and the tooz mysql driver passes lock names raw
into `GET_LOCK()`, which MySQL/Percona 8.0 hard-rejects (error 4163).
On top of that, `GET_LOCK` locks are local to the server a session is
connected to and are not Galera-replicated, so the mysql driver never
provided real cross-node exclusion behind the HA frontend.

The follow-up cinder change drops the mysql `backend_url` and points
tooz at this tier via the `redis://` driver (valkey is
protocol-compatible with redis), restoring working distributed locks.

Rejected alternatives: etcd (fine, but valkey is preferred for reuse
potential and operator familiarity); patching the tooz mysql driver to
hash long names (carries a local patch and keeps the Galera locality
caveat); per-cluster valkey processes on separate ports (more chef
surface for negligible benefit at this load).

## Topology

- One `valkey-server` per mq node: mq1 primary, mq2/mq3 replicas
  (`replicaof`), all requiring the shared password.
- `valkey-sentinel` on all three nodes monitoring service `oslocks`,
  quorum 2. Sentinel handles primary failover; clients discover the
  current primary through sentinel on 26379.
- One shared instance serves all three clouds, separated by redis db
  index: x86 db 0, arm db 1, ppc db 2. tooz additionally namespaces its
  keys under `_tooz`.
- Packages from EL10 AppStream: the single `valkey` package ships both
  `valkey.service` and `valkey-sentinel.service` with configs under
  `/etc/valkey/`.
- `maxmemory-policy noeviction` (an evicted lock key is a silently
  released lock) and `appendonly yes` (held locks survive a restart).
- `min-replicas-to-write 1` on the tier: a primary that loses both
  replicas refuses writes, so a partitioned ex-primary cannot keep
  granting locks the promoted side does not see.

## Chef pieces

- The valkey/sentinel mechanics (package, seed-once configs, services,
  OSL-only firewall, operator tooling) live in the reusable
  **osl-valkey** cookbook (`osl_valkey` + `osl_valkey_sentinel`
  resources).
- [resources/coordination.rb](../resources/coordination.rb): maps the
  tier topology onto those resources: primary/replica from the data
  bag `primary` vs the node's hostname, quorum from the `endpoint`
  count, lock-service settings (noeviction, AOF,
  `min-replicas-to-write 1` when clustered so an isolated ex-primary
  goes read-only instead of granting locks the rest of the cluster
  cannot see).
- [recipes/ops_coordination.rb](../recipes/ops_coordination.rb): thin
  wrapper reading the `coordination` block of the node's `openstack`
  data bag item. Add it to the mq node run lists alongside
  `ops_messaging`.

### Seed-once configs (`config_version`)

Both config files are rewritten by the daemons at runtime: sentinel
persists its myid, config epoch, discovered replicas/sentinels and
failover state; valkey persists its replication role when sentinel
promotes or demotes it. A plain chef template would fight those
rewrites and re-point a promoted primary back at the seeded topology on
every converge.

So chef seeds each file once and records
`coordination.config_version` (default 1) in a marker file
(`/etc/valkey/.valkey.conf.chef`, `/etc/valkey/.sentinel.conf.chef`).
To push a config change: bump `config_version` in the data bag and
converge. This re-renders both files from the template, restarts the
services, and resets any runtime failover state back to the configured
topology (mq1 primary), so treat a bump as a small maintenance action,
not a routine converge.

Known risks of the seed-once model:

- **Template edits without a version bump apply only to future
  seeds.** An existing node keeps its old config; a rebuilt node gets
  the new one. Any template change must ship with a `config_version`
  bump to reach the fleet.
- **Drift is invisible to chef.** Manual edits (or anything else that
  touches the files) are never detected or reverted. The NRPE checks
  are the guard against the failure modes that matter (auth, eviction
  policy, replication, quorum), not converge-time enforcement.
- **A re-seed is topology-affecting.** If sentinel promoted mq2 in the
  meantime, the bump demotes it back to replica-of-mq1 and restarts
  everything; locks held across that window on the demoted primary can
  be lost. Cinder tooz locks are short-lived, so the blast radius is a
  racing attach/detach, but schedule bumps like a small maintenance.
- **A stale ex-primary must not be re-seeded in isolation.** mq1
  restored from an old snapshot and re-seeded as primary would serve
  an empty/stale lock db while mq2/mq3 still follow the sentinel-
  elected primary. Rebuild members without markers join per the seeded
  topology; verify replication state afterwards.

### Data bag schema

The `coordination` block, in the tier's own bag item
(`messaging_tier`) and, for the client keys, in each cloud's item:

```json
"coordination": {
  "endpoint": ["mq1.bak.osuosl.org", "mq2.bak.osuosl.org", "mq3.bak.osuosl.org"],
  "primary": "mq1.bak.osuosl.org",
  "pass": "<openssl rand -hex 20>",
  "db": 0
}
```

- `endpoint`: all tier nodes; sizes the sentinel quorum ((N/2)+1) on
  the tier and provides the sentinel fallback list to clients.
- `primary`: initial primary; a node whose short hostname doesn't match
  becomes a replica. Omit for a standalone single node (kitchen suite).
- `pass`: valkey password (requirepass/masterauth, and the client
  password). Keep it URL-safe (hex): it is embedded in `backend_url`.
- `db`: client-side only; per-cloud database index (x86 0, arm 1,
  ppc 2). The tier ignores it.
- Optional: `service_name` (default `oslocks`), `down_after_ms`
  (5000), `failover_timeout_ms` (60000), `config_version` (1).

### Security

valkey requires the password for every client. Sentinel could too
(osl-valkey exposes `requirepass` for it), but this tier deliberately
leaves it unset: tooz 2.10.1 (yoga, verified on all three clusters) has
no way to send a sentinel password - its redis driver only passes the
userinfo password to the elected primary - so a sentinel that demanded
one would lock cinder out. That is a client limitation, not a sentinel
one; if a future tooz gains support, set `requirepass` and drop the
exception. Until then sentinel exposure is limited by the OSL-only
firewall on 26379 (same trust level as the rabbitmq management ports).
Sentinel authenticates itself to the monitored valkeys via `auth-pass`.

## Production deployment

The tier reuses the existing mq nodes, so this is a data bag edit plus
a run list addition. Everything else (package, configs, firewall,
services) is chef-managed.

1. Generate the shared password (`openssl rand -hex 20`) and add the
   `coordination` block (schema above, without `db`) to the
   `messaging_tier` bag item:

   ```bash
   knife data bag edit openstack messaging_tier
   ```

2. Add the recipe to each mq node, converging mq1 (the primary) first
   so replicas have something to sync from:

   ```bash
   # per node, mq1 first:
   knife node run_list add mq1.bak.osuosl.org 'recipe[osl-openstack::ops_coordination]'
   ssh mq1.bak.osuosl.org cinc-client
   # verify (step 3 subset), then repeat for mq2, then mq3
   ```

3. Verify the tier. `valkey-status` (installed by osl-valkey) shows
   sentinel's view plus live replication state of every member in one
   shot; the raw commands are the fallback:

   ```bash
   valkey-status                                      # exit 0, all members healthy

   # or by hand, on each node:
   systemctl is-active valkey valkey-sentinel
   valkey-cli ping                                    # NOAUTH error
   valkey-cli -a "$PASS" --no-auth-warning ping       # PONG
   valkey-cli -a "$PASS" --no-auth-warning info replication
   valkey-cli -p 26379 sentinel ckquorum oslocks
   ```

4. Failover validation, before any cloud points at the tier: stop
   valkey on mq1, confirm a replica is promoted within
   `down-after-milliseconds` plus election time, then restart mq1 and
   confirm it rejoins as a replica of the new primary:

   ```bash
   ssh mq1.bak.osuosl.org sudo systemctl stop valkey
   # from mq2: watch the promotion
   valkey-cli -p 26379 sentinel master oslocks   # ip flips off mq1
   ssh mq1.bak.osuosl.org sudo systemctl start valkey
   valkey-status                                 # mq1 back as a replica, link up
   ```

   That is the crash-style test. For planned maintenance on the
   primary (patching, reboot), use `valkey-failover` instead: it
   preflights replica ack, triggers a sentinel failover, and waits for
   the switch, so the primary moves before you take the node down.

   Note chef does not demote/promote anything at runtime; sentinel
   owns the topology after the seed. A converge during or after a
   failover is a no-op on the configs.

## Client side (follow-up change)

Each cloud's `cinder.conf` gets, via its data bag item's
`coordination` block:

```ini
[coordination]
backend_url = redis://:<pass>@mq1:26379?sentinel=oslocks&sentinel_fallback=mq2:26379&sentinel_fallback=mq3:26379&db=<N>
```

Controllers need `python3-redis` (in the yoga RDO repos, noarch, all
arches). Rollout x86 first (it has the known-broken attach to verify
against), then arm, then ppc. Verification per cloud: attach/detach
smoke test on a scratch VM, stuck `reserved` attachments cleaned up,
and lock keys visible during an attach:

```bash
valkey-cli -a "$PASS" --no-auth-warning -n <db> --scan --pattern '_tooz*'
```

## Monitoring

NRPE (chef-managed, via `osl-openstack::mon` on `node_type: messaging`
when the bag item has a `coordination` block):

- `check_valkey`: authenticated PING (reads requirepass root-only via
  the same sudo grant pattern as the rabbitmq checks)
- `check_valkey_replication`: primary has all expected replicas
  connected, or replica link is up (survives failovers; it checks the
  current role, not the seeded one)
- `check_valkey_sentinel`: `sentinel ckquorum` + all other members'
  sentinels discovered (no auth needed)

Remaining manual work mirrors the rabbitmq tier: Nagios server service
definitions for the new checks. Page on ping/quorum failures; a lock
service outage breaks volume attach on all three clouds at once.

Prometheus: valkey has no built-in metrics endpoint, so this needs a
`redis_exporter` deployment plus a scrape job for the mq nodes, both
of which belong in the **osl-prometheus** cookbook (the
`osl_prometheus_exporter` resource is the pattern). Follow-up there,
not in this cookbook.
