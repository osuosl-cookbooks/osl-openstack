# Nova Flavor Sync Tool

## Overview

The `nova-fix-flavors.py` script synchronizes OpenStack Nova instance RequestSpecs with current Flavor Extra Specs definitions. This is critical for fixing live migration issues where VMs aren't being placed on correct host aggregates due to stale flavor specifications.

## Problem Statement

When you modify flavor extra specs (especially `aggregate_instance_extra_specs`) **after** VMs have been created, the existing VMs retain the old flavor specifications in their `RequestSpec` database record. This causes the Nova scheduler to use outdated constraints during operations like live migration, resulting in incorrect VM placement.

## Solution

This tool:
- Reads current flavor definitions from the database
- Compares them with the RequestSpecs stored for each VM instance
- Updates stale RequestSpecs to match current flavor definitions
- Creates backups before making changes
- Provides dry-run and verbose modes for safe validation
- Supports restoring from backups if needed

## Installation

The script is deployed to controller nodes via the `compute_controller` recipe:

```bash
# Included automatically in the compute_controller recipe
# Files deployed to:
# /root/nova-fix-flavors.py          (executable script)
# /root/.nova-flavor-fixes/backups/   (backup directory)
# /root/.nova-flavor-fixes/nova-flavor-sync.log (log file)
```

## Usage

The script can be run directly (it has a shebang) or with `python3`:

```bash
./nova-fix-flavors.py [options]
# or
python3 /root/nova-fix-flavors.py [options]
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `--run` | Actually update the database (default is dry-run) |
| `--verify` | Verify only - check for mismatches without logging |
| `--verbose` | Show detailed spec differences and progress |
| `--no-backup` | Skip creating backup before running in live mode |
| `--restore BACKUP_FILE` | Restore request_specs from a backup file |
| `--list-backups` | List available backup files |

### 1. Dry Run (Default - Safe)

```bash
./nova-fix-flavors.py
```

Shows what would be changed without making any modifications:

```
[2026-01-06 14:32:10] [INFO] === Starting Flavor Sync ===
[2026-01-06 14:32:10] [INFO] Mode: DRY RUN
[2026-01-06 14:32:10] [INFO] Connecting to database: nova_api@localhost
[2026-01-06 14:32:11] [INFO] Loaded 42 active flavors
[2026-01-06 14:32:11] [INFO] Found 156 request specs
[2026-01-06 14:32:12] [INFO] === Sync Complete ===
[2026-01-06 14:32:12] [INFO] Summary: Updated=8, Skipped=148, Errors=0
[2026-01-06 14:32:12] [INFO] >>> To apply changes, run: python3 fix-flavors.py --run
```

### 2. Verbose Mode (Shows Details)

```bash
./nova-fix-flavors.py --verbose
```

Displays detailed information about each mismatch:

```
[2026-01-06 14:32:11] [INFO] Mismatch: abc123-uuid (Flavor: 68a71a9b-69f0-42ab-bb5a-38a85e3382ec)
[2026-01-06 14:32:11] [INFO]   Changes: {'aggregate_instance_extra_specs:storage_type': 'ceph'}
```

### 3. Verify Only Mode (No Logging)

```bash
./nova-fix-flavors.py --verify
```

Same as dry-run but minimal logging output.

### 4. Live Run (Actually Update Database)

```bash
./nova-fix-flavors.py --run --verbose
```

**Warning:** This will modify your Nova database. Always run in dry-run mode first!

The script will:
1. Create an automatic backup (unless `--no-backup` is used)
2. Update RequestSpec records
3. Commit changes to database
4. Log all changes

### 5. Live Run Without Backup

```bash
./nova-fix-flavors.py --run --no-backup
```

Use only if space is constrained. Backup is normally saved to `/root/.nova-flavor-fixes/backups/`.

### 6. List Available Backups

```bash
./nova-fix-flavors.py --list-backups
```

Shows all backup files with their record counts:

```
[2026-01-06 14:35:00] [INFO] === Available Backups ===
[2026-01-06 14:35:00] [INFO]   request_specs_20260106_143210.json - 156 records - 20260106_143210
[2026-01-06 14:35:00] [INFO]   request_specs_20260105_091532.json - 154 records - 20260105_091532
```

### 7. Restore from Backup (Dry Run)

```bash
./nova-fix-flavors.py --restore /root/.nova-flavor-fixes/backups/request_specs_20260106_143210.json
```

Shows what would be restored without making changes:

```
[2026-01-06 14:40:00] [INFO] === Starting Restore from Backup ===
[2026-01-06 14:40:00] [INFO] Mode: DRY RUN
[2026-01-06 14:40:00] [INFO] Backup file: /root/.nova-flavor-fixes/backups/request_specs_20260106_143210.json
[2026-01-06 14:40:00] [INFO] Backup timestamp: 20260106_143210
[2026-01-06 14:40:00] [INFO] Records in backup: 156
[2026-01-06 14:40:01] [INFO] === Restore Complete ===
[2026-01-06 14:40:01] [INFO] Summary: Restored=156, Skipped=0, Errors=0
[2026-01-06 14:40:01] [INFO] >>> To apply restore, run: ./nova-fix-flavors.py --restore /root/.nova-flavor-fixes/backups/request_specs_20260106_143210.json --run
```

### 8. Restore from Backup (Apply)

```bash
./nova-fix-flavors.py --restore /root/.nova-flavor-fixes/backups/request_specs_20260106_143210.json --run
```

Actually restores all RequestSpecs from the backup file.

## Examples

### Scenario 1: Fix Stale Aggregates After Flavor Update

```bash
# 1. You updated flavor extra specs
openstack flavor set --property aggregate_instance_extra_specs:storage_type=ceph m1.xlarge

# 2. Check what would change
./nova-fix-flavors.py --verbose

# 3. Apply the fix
./nova-fix-flavors.py --run --verbose

# 4. Verify migration works now
openstack server migrate --live <instance-uuid>
```

### Scenario 2: Recover from Incorrect Migration

```bash
# 1. Check RequestSpecs
./nova-fix-flavors.py

# 2. If mismatches found, apply fix
./nova-fix-flavors.py --run

# 3. Backup is created automatically:
ls -la /root/.nova-flavor-fixes/backups/
```

### Scenario 3: Rollback After Problematic Sync

```bash
# 1. List available backups
./nova-fix-flavors.py --list-backups

# 2. Dry-run the restore to verify
./nova-fix-flavors.py --restore /root/.nova-flavor-fixes/backups/request_specs_20260106_143210.json

# 3. Apply the restore
./nova-fix-flavors.py --restore /root/.nova-flavor-fixes/backups/request_specs_20260106_143210.json --run
```

## Database Backups

Backups are created automatically in `/root/.nova-flavor-fixes/backups/` with format:

```
request_specs_20260106_143210.json
request_specs_20260105_141532.json
```

Each backup contains:
- Timestamp of backup
- Count of request specs backed up
- Full JSON data for all specs

### Listing Backups

```bash
./nova-fix-flavors.py --list-backups
```

### Restoring from Backup

The script includes built-in restore functionality:

```bash
# Dry-run first to see what would be restored
./nova-fix-flavors.py --restore /root/.nova-flavor-fixes/backups/request_specs_20260106_143210.json

# Apply the restore
./nova-fix-flavors.py --restore /root/.nova-flavor-fixes/backups/request_specs_20260106_143210.json --run
```

The restore process:
1. Reads the backup JSON file
2. Checks if each record still exists in the database
3. Updates matching records with original spec data
4. Skips records that no longer exist (deleted VMs)
5. Reports summary of restored/skipped/error counts

## Troubleshooting

### Database Connection Error

Verify Nova configuration:

```bash
grep -A 5 "\[api_database\]" /etc/nova/nova.conf
```

The connection string should be readable by root.

### No Changes Detected

This is normal! It means all RequestSpecs are already synchronized with current flavors:

```
Summary: Updated=0, Skipped=148, Errors=0
```

### Changes Not Applied

If you ran in dry-run mode, you'll see:

```
>>> To apply changes, run: python3 fix-flavors.py --run
```

Always use `--run` flag to actually update the database.

## Log Files

- Main log: `/root/.nova-flavor-fixes/nova-flavor-sync.log`

View recent changes:

```bash
tail -50 /root/.nova-flavor-fixes/nova-flavor-sync.log
```

## Safety Features

1. **Dry-Run by Default** - No changes without `--run` flag
2. **Automatic Backups** - Saved before any modifications
3. **Built-in Restore** - Use `--restore` to rollback from backup
4. **Error Handling** - Skips malformed specs, reports errors
5. **Validation** - Checks database connectivity first
6. **Progress Tracking** - Reports every 100 specs processed (with `--verbose`)
7. **Logging** - All operations logged to file

## Related Commands

### Check Flavor Extra Specs

```bash
openstack flavor show m1.xlarge -c properties
```

Output:
```
+------------+----------------------------------------------------+
| Field      | Value                                              |
+------------+----------------------------------------------------+
| properties | aggregate_instance_extra_specs:storage_type='ceph' |
+------------+----------------------------------------------------+
```

### Check Aggregate Metadata

```bash
openstack aggregate show ceph -c metadata
```

Output:
```
+----------+---------+
| Field    | Value   |
+----------+---------+
| metadata | storage_type='ceph' |
+----------+---------+
```

### Verify Flavor Applied to VM

```bash
openstack server show <uuid> -c flavor
```

### Test Live Migration

```bash
# Without host (scheduler picks best)
openstack server migrate --live <uuid>

# Check result
openstack server show <uuid> -c 'OS-EXT-SRV-ATTR:host'
```

## Additional Resources

- [OpenStack Flavor Documentation](https://docs.openstack.org/nova/latest/admin/flavors.html)
- [Host Aggregates Guide](https://docs.openstack.org/nova/latest/admin/aggregates.html)
- [Live Migration](https://docs.openstack.org/nova/latest/admin/live-migration-usage.html)
