# OpenStack release upgrades

How a cloud moves from one OpenStack release to the next (yoga to zed first).
Chef prepares every node ahead of time but never moves one across a release.
The move happens in one window per cloud, driven from the jumphost. Before
`controller-db` starts, a rollback loses nothing; after it, a rollback
restores the databases and loses every write since `backup`.

## The pieces

### The `release` key

Each cloud's `openstack` data bag item (`x86`, `arm`, `ppc64`) can set
`release`. With no `release`, the target is `yoga`. On every converge,
`osl_openstack_client` compares the target with the release the node runs:

| Node | What Chef does |
|---|---|
| No venv RPMs yet (a new node) | Installs the oldest release the cloud's controllers report, so a hypervisor added mid-staging joins on what the cloud runs. Only with no controllers reporting (a new cloud) does it install the target |
| Runs the target | Nothing new; keeps upgrading within it |
| The target is the next release | Stages it (below), and keeps the node on what it runs |
| The target is older than what it runs | Raises: undo the node first, then set `release` back |
| The target skips a release | Raises |
| Mixed release markers installed | Raises |

The installed release comes from the venv RPMs' `osuosl-openstack-release(<rel>)`
markers; venv RPMs without one are yoga. The releases, in order, are
`openstack_releases` in `libraries/helpers.rb`.

**Staging** writes a disabled `OSL-openstack-<release>` repo and downloads
the release's RPMs once (`dnf --downloadonly`, behind
`/var/lib/osl-openstack/staged-<release>`). Nothing reads a disabled repo
unless a command passes `--enablerepo`, so dnf-automatic and Chef's own
package resources keep using the running release.
If `openstack/<release>/` isn't published for the node's arch yet, Chef logs
a warning and skips staging; enabling an unpublished repo fails every dnf call.
Once the node runs the release, or the bag stops targeting it, Chef removes
the staging repo and its marker, so setting `release` again restages.

Each node publishes `node['osl-openstack']['release']` (`installed`, `target`,
`staged`; a new node reports the release its first run installs), and controllers publish `node['osl-openstack']['db_node']`. The
same goes to `/etc/osl-openstack/release.json`.

### `openstack-node-upgrade` (every OpenStack node)

| Command | Where | What it does |
|---|---|---|
| `status` | any | JSON: release state, markers, units, the recorded transaction, cron |
| `stop` | any | Removes the cinc cron, kills a cron run still in its splay sleep, waits (up to an hour) for a running converge by taking `/tmp/chef-client.lock`, then stops every unit the venv RPMs ship (and httpd on controllers) |
| `install` | any | Saves the running release's repo as the disabled `OSL-openstack-rollback`, installs the staged release and records the dnf transaction |
| `undo` | any | `dnf history undo` of that transaction, from `OSL-openstack-rollback` |
| `precheck` | DB controller | nova-compute service versions >= 61 in every cell, yoga online migrations done, `/root/nova-resize-debris-check.py --exit-code` clean |
| `backup` | DB controller | `mysqldump` of every service database to `/root/openstack-upgrade-backup/<release>/` |
| `restore` | DB controller | Prints, then with `--yes` runs, the restore of those dumps |
| `check` | any | Every `*-status upgrade check`; fails on rc >= 2 |
| `migrate` | DB controller | nova, cinder and placement `online_data_migrations` until done |
| `restart-nova` | controllers | conductor, scheduler, then the API apps, to lift the RPC version caps |

It logs to `/var/log/openstack-node-upgrade.log`. Credentials never reach a
command line: they go to `mysqldump` and `mysql` through 0600 option files.
`stop` only waits out converges that take the cron's lock; don't start a
bare `cinc-client` by hand during a window. The rollback repo stays,
disabled, until the next upgrade's `install` overwrites it. `undo` needs
every version the transaction replaced still published.

### `openstack-upgrade` (jumphost)

`recipe[osl-openstack::upgrade_runner]` on the jumphost writes
`/etc/openstack-upgrade/<cloud>.json` from node search (controllers, the DB
controller, hypervisors, canaries) and installs
`/usr/local/sbin/openstack-upgrade <cloud> <phase>`. It runs
`openstack-node-upgrade` and `cinc-client` over `ssh root@<host>`, refuses a
phase until the earlier ones are done, and keeps markers in
`/root/openstack-upgrade/<cloud>-<release>/` so a window can resume.
`--dry-run` prints what would run. Logs go to `/var/log/openstack-upgrade/`.

Canaries are hypervisors with `node['osl-openstack']['upgrade_canary']` set,
otherwise the first hypervisor of each CPU model (one POWER9 and one POWER10
on ppc64).

## Before the window

0. Once, after every controller runs this cookbook (they publish `db_node`):
   `knife node run_list add jumphost.osuosl.org 'recipe[osl-openstack::upgrade_runner]'`,
   converge the jumphost, and check `/etc/openstack-upgrade/{x86,arm,ppc64}.json`.
1. Publish the target release to `openstack/<release>/` for every arch. No node
   reads that path yet, so this deploys nothing.
2. Set `release` in the cloud's data bag item. Every node stages on its next
   converge (cron, within 30 minutes).
3. `openstack-upgrade <cloud> status` until every node shows `staged=True`.
4. Draft the status.io maintenance and the hosting-list email.
5. `openstack-upgrade <cloud> precheck`. Fix what it reports; it can be rerun.

## The window

| Phase | What happens |
|---|---|
| `stop` | Both controllers stop: the API, scheduler and conductor are down. Instances, HA routers, DHCP and the metadata proxies keep running: the agents start keepalived, dnsmasq and haproxy through `sudo neutron-rootwrap-daemon`, which puts them in root's `session-*.scope`, outside the agent units. Set Nagios downtime on the cloud's `check_{keystone,glance,nova,nova_placement,neutron,cinder,heat}_api` and `check_novnc` |
| `backup` | Refuses unless every OpenStack unit on both controllers is stopped, then dumps every service database on the DB controller |
| `controller-db` | Installs and converges the DB controller; the converge runs the db syncs, starts its services and restores its cron. haproxy sends users to it right away. **Points of no return 1 and 2** |
| `controller` | Installs and converges the other controller, which restores its cron |
| `verify` | Upgrade checks and the compute, network and volume service lists |
| `computes` | Canaries one at a time, a pause to check them, then batches of `--batch` (default 2); it stops after a batch with a failed host |
| `finalize` | Restarts nova on both controllers, runs the online migrations to completion, checks again, and converges the controllers |

From `controller-db` on, users write through the new release, and a restore
loses everything written since `backup`. Fix forward once that loss is
unacceptable.

## Rollback

| Where the window stopped | Steps | Data |
|---|---|---|
| `controller-db` never started (no `controller-db.started` marker) | `openstack-upgrade <cloud> rollback`, set `release` back, then `rollback --converge` | Nothing lost |
| `controller-db` started | `openstack-node-upgrade stop` on every controller that ran install, then `restore --yes` on the DB controller; `rollback --restored`, set `release` back, `rollback --converge`; then `openstack-node-upgrade check` on the DB controller and `openstack-upgrade <cloud> status` | Writes since `backup` are lost |
| Once losing the writes since `backup` is unacceptable | Fix forward | A restore would lose them |

Undo comes before reverting the bag, in that order: Chef raises on a node
whose installed release is newer than the bag, which is the safety net.
`rollback` takes the target from the controllers, lists any hypervisor it
can't reach for a hand `openstack-node-upgrade undo`, and moves the window's
phase markers to `/root/openstack-upgrade/<cloud>-<release>.rolled-back-<UTC>`,
so a retry starts again at `precheck`. `rollback --converge` needs no
agreement on the target and keeps going past a failed host.
`openstack-upgrade --help-rollback` prints this sequence.

## Rehearsal in multi-node

The multi-node suite has a `jumphost` VM running the runner, with a test root
key trusted by both controllers and the compute.

1. Converge the suite, then `terraform output jumphost`.
2. Set `"release": "zed"` in `test/integration/data_bags/openstack/multinode.json`
   and upload it: `CHEF_SERVER="$(terraform output -raw chef_zero)" knife data bag from file openstack test/integration/data_bags/openstack/multinode.json -c test/chef-config/knife.rb`.
3. `cinc-client` on controller1, controller2 and compute to stage zed.
4. On the jumphost, as root: `openstack-upgrade multinode status`, then each
   phase in order, timing them.
5. Rehearse a rollback after `controller`. To run the window again, set
   `"release": "zed"` again, upload it, converge the three nodes to restage,
   and start over at `precheck`.

The suite has one compute, so it can't test a live migration between a yoga
and a zed hypervisor.

## Adding the next release

1. Build its RPMs on a new packaging line (`references/new-release.md` in the
   openstack-packaging skill); they provide `osuosl-openstack-release(<rel>)`.
2. Append it to `openstack_releases`.
3. Recheck `precheck`'s minimum compute version (`MIN_COMPUTE_VERSION` in
   `files/openstack-node-upgrade.py`) against the new release's
   `OLDEST_SUPPORTED_SERVICE_VERSION`, and the status and migration commands.
