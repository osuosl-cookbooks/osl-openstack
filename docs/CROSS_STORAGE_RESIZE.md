# Resizes Between Ceph and Local Storage

## Overview

A resize or cold migration that moves an instance between a Ceph-backed
compute and a local-storage compute does not move its root disk. The guest
comes back `ACTIVE` on a fresh disk built from its image, nothing reports an
error, and the tenant's data is on the old disk, which nova leaves behind.
This page covers how storage is marked in each cloud, why nova behaves this
way, how to spot a move that crossed, and how to put the old disk back with
`nova-restore-local-disk`.

Instances that boot from a Cinder volume are unaffected: their root moves
with them.

## How storage is marked

The scheduler keeps instances on the right storage through one aggregate
metadata key per cloud, matched by the same key in the flavor's extra specs
(`AggregateInstanceExtraSpecsFilter`). Nothing stops a resize to a flavor
that carries the other value.

| Cloud | Aggregate key | Values | Flavor spec |
|---|---|---|---|
| x86 | `storage_type` | `ceph`, `local` | `aggregate_instance_extra_specs:storage_type` |
| ppc64 | `local_storage` | `true`, `false` | `aggregate_instance_extra_specs:local_storage` |
| aarch64 | none | all Ceph | none |

Local-storage flavors follow a naming pattern (`*.local.*` on x86, the
POWER10 and `p9.nvme.*` flavors on ppc64). A flavor without the spec can land
on either storage type; section 9 of `nova-resize-debris-check` lists them.
Check which hosts a flavor's instances already run on before adding the spec,
because the next cold migration of each one follows the flavor.

```bash
openstack aggregate list --long -f json              # hosts and metadata
openstack flavor show <flavor> -c properties
```

## What nova does

Verified at nova 25.3.0 (Yoga, deployed), unchanged at 26.3.0, in
`nova/virt/libvirt/driver.py`:

- `migrate_disk_and_power_off` copies only `file` and `block` disks, so an
  RBD root is skipped. The destination's image backend then creates a new
  root from the Glance image.
- `finish_migration` carries upstream's own note that converting between
  the lvm and rbd backends is not supported.
- `_cleanup_resize`, run by the confirm, removes the `<uuid>_resize`
  directory and the `nova-resize` RBD snapshot, never the RBD image itself.

So:

- **Ceph to local**: the old root survives as `<pool>/<uuid>_disk` (the pool
  is `vms` on x86) until someone removes it. Recoverable, even after the
  confirm.
- **Local to Ceph**: the old local disk sits in the source host's
  `<uuid>_resize` directory only until the confirm removes it. Recoverable
  only while the instance is in `VERIFY_RESIZE`: revert, never confirm.

Nova has no option or filter that blocks this. An OSL patch for nova-api is
planned for after the Zed upgrade.

## Spotting a move that crossed

`nova-resize-debris-check` section 9, on a controller with an admin openrc
sourced, reports:

- resizes and cold migrations whose source and destination sit in different
  storage aggregates (a finding while the old root is still in the pool,
  or while the move is unconfirmed; a note otherwise);
- live instances whose flavor spec disagrees with their host's aggregate;
- `<uuid>_disk` images whose instance is gone, or now runs on local
  storage;
- flavors without the storage spec.

By hand:

```bash
openstack --os-compute-api-version 2.80 server migration list -f json   # source and dest hosts
openstack aggregate list --long -f json                                  # which host is which
openstack server event list <uuid> --long -f json                        # who did the resize
rbd --id <rbd_user> -p vms info <uuid>_disk                              # the old root, if any
```

Hosts that changed storage type since a move cannot be classified against
today's aggregates; the tool counts those rather than guessing.

## Recovery after a Ceph-to-local move

One step at a time; every write here is deliberate.

### 1. Protect the old root first

An image with no instance on Ceph looks like a leak to anyone cleaning the
pool, and a protected snapshot makes `rbd rm` fail:

```bash
rbd --id <rbd_user> -p vms info <uuid>_disk        # modify_timestamp ~1 min after the resize
rbd --id <rbd_user> snap create vms/<uuid>_disk@<TICKET>-preserve
rbd --id <rbd_user> snap protect vms/<uuid>_disk@<TICKET>-preserve
```

### 2. Offer the tenant three options

Keep a copy of their current disk whichever they pick; they have written to
it since the resize.

- attach the old disk as a second disk (copy it into a Cinder volume);
- put it back as the root disk on a Ceph flavor by hand, never by having
  the tenant resize back (that would leave the local disk behind in turn);
- convert it onto the current local disk in place (below; this is the one
  that has been run at OSL).

### 3. Convert onto the local disk with `nova-restore-local-disk`

The tool is installed on every local-storage compute. It needs the host's
Ceph client (`ceph-common`, `qemu-kvm-block-rbd`) and nova's `rbd_user`
key, which the Ceph compute role already provides.

On a controller, stop the instance through nova and wait for `SHUTOFF`:

```bash
openstack server stop <uuid>
openstack server show <uuid> -c status -c OS-EXT-SRV-ATTR:host
```

On that compute, dry run first. Every guard runs and every command is
printed; nothing is written:

```bash
nova-restore-local-disk <uuid> <TICKET>-preserve
```

The guards refuse, with the reason, unless: `rbd`, `qemu-img`, `virsh` and
`chcon` are installed; nova.conf has an `rbd_user`; the domain is `shut
off`; `qemu-img info` opens `disk` without a lock and it is qcow2; the
snapshot exists and is protected; the `rbd:` source opens; the instance has
no ephemeral disk; no `disk.recovered*` or `disk.pre-<tag>` is left from an
earlier run; and the directory has room for the image.

Then run it:

```bash
nova-restore-local-disk --run <uuid> <TICKET>-preserve
```

It converts the snapshot to `disk.recovered.partial` (the clone reads
through its Glance parent, so the result is standalone), checks that the
result is a qcow2 with no backing file and passes `qemu-img check`, renames
it to `disk.recovered`, grows it to the current disk's virtual size (the
size nova built at the new flavor; `--size <GiB>` overrides, and a disk is
never shrunk), copies owner, mode and SELinux context from the current
disk, and only then swaps: `disk` becomes `disk.pre-<tag>` and
`disk.recovered` becomes `disk`. The rollback is printed:

```bash
mv disk disk.recovered && mv disk.pre-<tag> disk
```

`disk.info` stays as it is: a qcow2 with no backing file boots fine, since
nova skips an existing disk that has none.

Back on the controller:

```bash
openstack server start <uuid>
```

The guest's growpart extends the root filesystem on first boot. Its old SSH
host keys come back with it; tell the tenant. The console cannot tell the
old system from a fresh one (same image, same root filesystem UUID); the
tenant's own check confirms it.

| Option | Default | Meaning |
|---|---|---|
| `--run` | off | do it (otherwise dry run) |
| `--rbd-pool POOL` | `vms` | pool holding `<uuid>_disk` |
| `--size GIB` | current disk's size | grow the recovered disk to this |
| `--tag TAG` | the snapshot name | the kept disk becomes `disk.pre-TAG` |
| `--instances-dir DIR` | `/var/lib/nova/instances` | |
| `--nova-conf FILE` | `/etc/nova/nova.conf` | where `rbd_user` is read |

Exit 0 means done (or a clean dry run), 1 a guard refused, 2 a step
failed; on 2 the tool prints what is left on disk.

### 4. Clean up only after the tenant confirms

```bash
rm /var/lib/nova/instances/<uuid>/disk.pre-<tag>                 # on the compute
rbd --id <rbd_user> snap unprotect vms/<uuid>_disk@<TICKET>-preserve
rbd --id <rbd_user> snap rm vms/<uuid>_disk@<TICKET>-preserve
rbd --id <rbd_user> rm vms/<uuid>_disk
```

## Recovery after a local-to-Ceph move

Only while the instance is still in `VERIFY_RESIZE`:

```bash
openstack server resize revert <uuid>
```

The revert reuses the local disk in the source's `<uuid>_resize` directory.
Once confirmed, that directory is gone and there is nothing to recover.

## Related

- [NOVA_FIX_FLAVORS.md](NOVA_FIX_FLAVORS.md): stale RequestSpecs after a
  flavor's specs change
- `nova-resize-debris-check` (section 9), `nova-restore-local-disk`
- The public warning for tenants lives in the OSL wiki under "Creating
  instances"
