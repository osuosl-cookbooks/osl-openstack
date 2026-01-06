#!/usr/bin/env python3
import json
import pymysql
import configparser
import argparse
import sys
import os
import datetime
import hashlib
from pathlib import Path
from sqlalchemy.engine.url import make_url

# --- CONFIGURATION ---
NOVA_CONF_PATH = '/etc/nova/nova.conf'
BACKUP_DIR = '/root/.nova-flavor-fixes/backups'
LOG_FILE = '/root/.nova-flavor-fixes/nova-flavor-sync.log'

def setup_logging(verbose=False):
    """Setup basic logging to file and console."""
    Path(BACKUP_DIR).mkdir(parents=True, exist_ok=True)
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    def log_msg(level, msg):
        log_entry = f"[{timestamp}] [{level}] {msg}"
        print(log_entry)
        try:
            with open(LOG_FILE, 'a') as f:
                f.write(log_entry + '\n')
        except IOError as e:
            print(f"Warning: Could not write to {LOG_FILE}: {e}")

    return log_msg

def get_db_params():
    """Reads nova.conf and parses the [api_database] connection string."""
    config = configparser.ConfigParser()
    if not os.path.exists(NOVA_CONF_PATH):
        print(f"Error: {NOVA_CONF_PATH} not found")
        sys.exit(1)

    config.read(NOVA_CONF_PATH)
    try:
        # RequestSpecs and Flavors are always in the api_database
        conn_str = config.get('api_database', 'connection')
    except (configparser.NoSectionError, configparser.NoOptionError):
        print(f"Error: Could not find [api_database] connection in {NOVA_CONF_PATH}")
        sys.exit(1)

    url = make_url(conn_str)
    return {
        'host': url.host,
        'user': url.username,
        'password': url.password,
        'db': url.database,
        'port': url.port or 3306,
        'charset': 'utf8mb4',
        'cursorclass': pymysql.cursors.DictCursor
    }

def get_canonical_flavor_specs(cursor, log_msg):
    """Builds a map of {flavor_id: {extra_specs_dict}} from current DB state."""
    log_msg("INFO", "Fetching current flavor definitions from DB...")

    # We try f.deleted_at IS NULL (modern) or f.deleted = 0 (legacy)
    # If the column 'deleted' is missing, it's likely a modern schema.
    sql = """
        SELECT f.flavorid, fes.key, fes.value 
        FROM flavors f 
        LEFT JOIN flavor_extra_specs fes ON f.id = fes.flavor_id 
    """

    # Check for the column existence to avoid the OperationalError
    cursor.execute("SHOW COLUMNS FROM flavors LIKE 'deleted'")
    has_deleted_int = cursor.fetchone()

    if has_deleted_int:
        sql += " WHERE f.deleted = 0"
    else:
        # Modern schemas use deleted_at
        cursor.execute("SHOW COLUMNS FROM flavors LIKE 'deleted_at'")
        if cursor.fetchone():
            sql += " WHERE f.deleted_at IS NULL"

    cursor.execute(sql)
    rows = cursor.fetchall()

    flavor_map = {}
    for row in rows:
        fid = row['flavorid']
        if fid not in flavor_map:
            flavor_map[fid] = {}

        if row['key']:
            flavor_map[fid][row['key']] = row['value']

    log_msg("INFO", f"Loaded {len(flavor_map)} active flavors")
    return flavor_map

def create_backup(cursor, backup_name, log_msg):
    """Creates a backup of request_specs table before modification."""
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = os.path.join(BACKUP_DIR, f"{backup_name}_{timestamp}.json")

    log_msg("INFO", f"Creating backup: {backup_file}")

    cursor.execute("SELECT id, instance_uuid, spec FROM request_specs")
    request_specs = cursor.fetchall()

    backup_data = {
        'timestamp': timestamp,
        'count': len(request_specs),
        'specs': [{'id': rs['id'], 'instance_uuid': rs['instance_uuid'], 'spec': rs['spec']}
                  for rs in request_specs]
    }

    try:
        with open(backup_file, 'w') as f:
            json.dump(backup_data, f, indent=2, default=str)
        log_msg("INFO", f"Backup created successfully ({len(request_specs)} records)")
        return backup_file
    except IOError as e:
        log_msg("ERROR", f"Failed to create backup: {e}")
        return None

def restore_backup(backup_file, dry_run=True):
    """Restore request_specs from a backup file."""
    log_msg = setup_logging(verbose=True)

    mode_label = "DRY RUN" if dry_run else "LIVE MODE"
    log_msg("INFO", f"=== Starting Restore from Backup ===")
    log_msg("INFO", f"Mode: {mode_label}")
    log_msg("INFO", f"Backup file: {backup_file}")

    if not os.path.exists(backup_file):
        log_msg("ERROR", f"Backup file not found: {backup_file}")
        sys.exit(1)

    try:
        with open(backup_file, 'r') as f:
            backup_data = json.load(f)
    except (IOError, json.JSONDecodeError) as e:
        log_msg("ERROR", f"Failed to read backup file: {e}")
        sys.exit(1)

    log_msg("INFO", f"Backup timestamp: {backup_data.get('timestamp', 'unknown')}")
    log_msg("INFO", f"Records in backup: {backup_data.get('count', 0)}")

    try:
        db_config = get_db_params()
        log_msg("INFO", f"Connecting to database: {db_config['db']}@{db_config['host']}")
    except Exception as e:
        log_msg("ERROR", f"Failed to read database config: {e}")
        sys.exit(1)

    connection = None

    try:
        connection = pymysql.connect(**db_config)
        log_msg("INFO", "Database connection successful")

        with connection.cursor() as cursor:
            restored_count = 0
            skipped_count = 0
            error_count = 0

            for spec_record in backup_data.get('specs', []):
                try:
                    record_id = spec_record['id']
                    instance_uuid = spec_record['instance_uuid']
                    original_spec = spec_record['spec']

                    # Check if record still exists
                    cursor.execute("SELECT id FROM request_specs WHERE id = %s", (record_id,))
                    if not cursor.fetchone():
                        log_msg("WARN", f"Record {record_id} ({instance_uuid}) no longer exists, skipping")
                        skipped_count += 1
                        continue

                    if not dry_run:
                        cursor.execute("UPDATE request_specs SET spec = %s WHERE id = %s",
                                      (original_spec, record_id))

                    restored_count += 1
                    log_msg("INFO", f"Restored: {instance_uuid}")

                except (KeyError, TypeError) as e:
                    log_msg("ERROR", f"Malformed backup record: {e}")
                    error_count += 1
                    continue

            if not dry_run:
                connection.commit()
                log_msg("INFO", "Database changes committed successfully")

            log_msg("INFO", "=== Restore Complete ===")
            log_msg("INFO", f"Summary: Restored={restored_count}, Skipped={skipped_count}, Errors={error_count}")

            if dry_run:
                log_msg("INFO", f">>> To apply restore, run: ./nova-fix-flavors.py --restore {backup_file} --run")

            return {'restored': restored_count, 'skipped': skipped_count, 'errors': error_count}

    except pymysql.Error as e:
        log_msg("ERROR", f"Database error: {e}")
        sys.exit(1)
    finally:
        if connection:
            connection.close()
            log_msg("INFO", "Database connection closed")

def list_backups():
    """List available backup files."""
    log_msg = setup_logging(verbose=False)
    log_msg("INFO", "=== Available Backups ===")

    if not os.path.exists(BACKUP_DIR):
        log_msg("INFO", "No backup directory found")
        return []

    backups = sorted(Path(BACKUP_DIR).glob("*.json"), reverse=True)

    if not backups:
        log_msg("INFO", "No backups found")
        return []

    for backup in backups:
        try:
            with open(backup, 'r') as f:
                data = json.load(f)
            count = data.get('count', 'unknown')
            timestamp = data.get('timestamp', 'unknown')
            log_msg("INFO", f"  {backup.name} - {count} records - {timestamp}")
        except (IOError, json.JSONDecodeError):
            log_msg("INFO", f"  {backup.name} - (unreadable)")

    return backups

def sync_specs(dry_run=True, verbose=False, verify_only=False, backup=True):
    """Synchronize VM RequestSpecs with current Flavor Extra Specs."""
    log_msg = setup_logging(verbose)

    mode_label = "VERIFY ONLY" if verify_only else ("DRY RUN" if dry_run else "LIVE MODE")
    log_msg("INFO", f"=== Starting Flavor Sync ===")
    log_msg("INFO", f"Mode: {mode_label}")

    try:
        db_config = get_db_params()
        log_msg("INFO", f"Connecting to database: {db_config['db']}@{db_config['host']}")
    except Exception as e:
        log_msg("ERROR", f"Failed to read database config: {e}")
        sys.exit(1)

    connection = None
    backup_file = None

    try:
        connection = pymysql.connect(**db_config)
        log_msg("INFO", "Database connection successful")

        with connection.cursor() as cursor:
            # Validate database connectivity
            cursor.execute("SELECT VERSION()")
            version = cursor.fetchone()
            log_msg("INFO", f"MySQL version: {version}")

            # Create backup if requested
            if backup and not verify_only and not dry_run:
                backup_file = create_backup(cursor, "request_specs", log_msg)
                if not backup_file:
                    log_msg("ERROR", "Backup creation failed. Aborting.")
                    sys.exit(1)

            # 1. Get current state of flavors
            canonical_flavors = get_canonical_flavor_specs(cursor, log_msg)

            # 2. Get all RequestSpecs
            log_msg("INFO", "Fetching all instance RequestSpecs...")
            cursor.execute("SELECT id, instance_uuid, spec FROM request_specs")
            request_specs = cursor.fetchall()
            log_msg("INFO", f"Found {len(request_specs)} request specs")

            updated_count = 0
            skipped_count = 0
            error_count = 0
            changes = []

            for idx, rs in enumerate(request_specs, 1):
                try:
                    if verbose and idx % 100 == 0:
                        log_msg("INFO", f"Processing: {idx}/{len(request_specs)}")

                    spec_json = json.loads(rs['spec'])
                    # Structure: request_spec -> flavor -> extra_specs
                    flavor_obj = spec_json['nova_object.data']['flavor']
                    flavor_data = flavor_obj['nova_object.data']
                    flavor_id = flavor_data['flavorid']

                    # Current extra specs stored in this VM's stale snapshot
                    current_vm_specs = flavor_data.get('extra_specs') or {}

                    # Target specs from the actual Flavor definition
                    target_specs = canonical_flavors.get(flavor_id)

                    if target_specs is None:
                        # This flavor may have been deleted, or it's a deleted VM
                        continue

                    # Compare (Dict comparison in Python is order-agnostic)
                    if current_vm_specs != target_specs:
                        updated_count += 1
                        change_record = {
                            'uuid': rs['instance_uuid'],
                            'flavor_id': flavor_id,
                            'old_specs': current_vm_specs,
                            'new_specs': target_specs
                        }
                        changes.append(change_record)

                        if verbose:
                            log_msg("INFO", f"Mismatch: {rs['instance_uuid']} (Flavor: {flavor_id})")
                            missing_or_changed = {k: target_specs.get(k) for k in set(list(current_vm_specs.keys()) + list(target_specs.keys()))
                                                 if current_vm_specs.get(k) != target_specs.get(k)}
                            log_msg("INFO", f"  Changes: {missing_or_changed}")

                        if not dry_run and not verify_only:
                            flavor_data['extra_specs'] = target_specs
                            updated_spec_str = json.dumps(spec_json)
                            cursor.execute("UPDATE request_specs SET spec = %s WHERE id = %s", 
                                           (updated_spec_str, rs['id']))
                    else:
                        skipped_count += 1

                except (KeyError, TypeError, json.JSONDecodeError) as e:
                    # Skip system-only or malformed request specs
                    error_count += 1
                    if verbose:
                        log_msg("WARN", f"Skipped malformed spec {rs['instance_uuid']}: {e}")
                    continue

            # Commit if in live mode
            if not dry_run and not verify_only:
                try:
                    connection.commit()
                    log_msg("INFO", "Database changes committed successfully")
                except pymysql.Error as e:
                    log_msg("ERROR", f"Database commit failed: {e}")
                    if backup_file:
                        log_msg("INFO", f"Backup saved at: {backup_file}")
                    sys.exit(1)

            # Summary
            log_msg("INFO", "=== Sync Complete ===")
            log_msg("INFO", f"Summary: Updated={updated_count}, Skipped={skipped_count}, Errors={error_count}")

            if updated_count > 0:
                if dry_run or verify_only:
                    log_msg("INFO", f">>> To apply changes, run: python3 fix-flavors.py --run")
                if backup_file:
                    log_msg("INFO", f">>> Backup available at: {backup_file}")

            return {
                'updated': updated_count,
                'skipped': skipped_count,
                'errors': error_count,
                'changes': changes,
                'backup': backup_file
            }

    except pymysql.Error as e:
        log_msg("ERROR", f"Database error: {e}")
        sys.exit(1)
    except Exception as e:
        log_msg("ERROR", f"Unexpected error: {e}")
        sys.exit(1)
    finally:
        if connection:
            connection.close()
            log_msg("INFO", "Database connection closed")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Sync VM RequestSpecs with current Flavor Extra Specs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run (default) - shows what would change
  ./nova-fix-flavors.py

  # Verify only - same as dry run but without output to log
  ./nova-fix-flavors.py --verify

  # Live run - actually update the database
  ./nova-fix-flavors.py --run

  # Verbose mode with detailed changes
  ./nova-fix-flavors.py --verbose --run

  # List available backups
  ./nova-fix-flavors.py --list-backups

  # Restore from backup (dry run first)
  ./nova-fix-flavors.py --restore /root/.nova-flavor-fixes/backups/request_specs_20260105_143210.json

  # Restore from backup (actually apply)
  ./nova-fix-flavors.py --restore /root/.nova-flavor-fixes/backups/request_specs_20260105_143210.json --run
        """
    )
    parser.add_argument('--run', action='store_true',
                        help="Actually update the database (default is dry-run)")
    parser.add_argument('--verify', action='store_true',
                        help="Verify only - check for mismatches without logging")
    parser.add_argument('--verbose', action='store_true',
                        help="Show detailed spec differences and progress")
    parser.add_argument('--no-backup', action='store_true',
                        help="Skip creating backup before running in live mode")
    parser.add_argument('--restore', metavar='BACKUP_FILE',
                        help="Restore request_specs from a backup file")
    parser.add_argument('--list-backups', action='store_true',
                        help="List available backup files")

    args = parser.parse_args()

    # Handle list-backups
    if args.list_backups:
        list_backups()
        sys.exit(0)

    # Handle restore
    if args.restore:
        result = restore_backup(args.restore, dry_run=(not args.run))
        if result['errors'] > 0:
            sys.exit(1)
        sys.exit(0)

    # Normal sync operation
    result = sync_specs(
        dry_run=(not args.run),
        verbose=args.verbose,
        verify_only=args.verify,
        backup=(not args.no_backup)
    )

    # Exit with appropriate code based on results
    if result['errors'] > 0:
        sys.exit(1)
    elif result['updated'] > 0:
        sys.exit(0)
    else:
        sys.exit(0)
