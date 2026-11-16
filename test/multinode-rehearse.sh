#!/bin/bash
# Multi-node release-upgrade rehearsal helpers (docs/RELEASE_UPGRADES.md); run after
# `KITCHEN_YAML=kitchen.multi-node.yml kitchen converge multi-node`.
set -euo pipefail

usage() {
  cat <<EOF
usage: $0 <command>
  stage <release>     upload the bag with that release, then cinc-client on every controller and compute
  jumphost            root tmux session "upgrade" on the jumphost, for precheck and upgrade
  vms                 upgrade_vms.sh check on controller1
  ssh <node> [cmd]    shell or command on a node (controller1, compute2, jumphost, ...)
  nodes               node names and IPs
EOF
}
cd "$(dirname "$0")/.."

BAG=test/integration/data_bags/openstack/multinode.json
KNOWN_HOSTS=.kitchen/multinode_known_hosts
NODES=(chef_zero database ceph mq1 mq2 mq3 controller1 controller2 compute compute2 compute3 jumphost)

# Empty for a node this build doesn't have (an extra compute's output is null)
ip() { terraform output -raw "$1" 2>/dev/null || true; }

# Rebuilt VMs reuse addresses, so the host keys start over after every apply
state="terraform.tfstate.d/$(terraform workspace show)/terraform.tfstate"
mkdir -p .kitchen
if [ -f "$state" ] && [ "$state" -nt "$KNOWN_HOSTS" ]; then
  rm -f "$KNOWN_HOSTS"
fi
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$KNOWN_HOSTS" -o LogLevel=ERROR)

addr() {
  local a
  a=$(ip "$1")
  [ -n "$a" ] || { echo "no $1 in this build (terraform output $1 is empty)" >&2; exit 1; }
  echo "$a"
}

# Runs a command on a node with its name on every output line
run_on() {
  local node=$1
  shift
  # shellcheck disable=SC2029 # the command is built here and run on the node
  ssh "${SSH_OPTS[@]}" "almalinux@$(addr "$node")" "$@" 2>&1 | sed -u "s/^/$node: /"
  return "${PIPESTATUS[0]}"
}

stage() {
  local release=${1:?usage: $0 stage <release>} failed=() pids=() node
  # The release lives in the fixture so every later upload (each converge) keeps it; yoga is
  # the default a bag without one means (libraries/helpers.rb), so it drops the line
  python3 - "$BAG" "$release" <<'PY'
import sys
path, release = sys.argv[1:]
lines = [l for l in open(path).readlines() if not l.lstrip().startswith('"release":')]
if release != 'yoga':
    at = next(i for i, l in enumerate(lines) if l.strip() == '"id": "multinode",')
    lines.insert(at + 1, f'  "release": "{release}",\n')
open(path, 'w').writelines(lines)
PY
  CHEF_SERVER=$(addr chef_zero) knife data bag from file openstack "$BAG" -c test/chef-config/knife.rb
  # controller1 is the DB node and runs the db syncs, so the controllers go one at a time
  for node in controller1 controller2; do
    run_on "$node" sudo cinc-client || failed+=("$node")
  done
  local computes=()
  for node in compute compute2 compute3; do
    [ -n "$(ip "$node")" ] && computes+=("$node")
  done
  for node in "${computes[@]}"; do
    run_on "$node" sudo cinc-client &
    pids+=($!)
  done
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}" || failed+=("${computes[$i]}")
  done
  if [ ${#failed[@]} -gt 0 ]; then
    echo "cinc-client failed on: ${failed[*]}" >&2
    exit 1
  fi
  echo "staged $release on controller1 controller2 ${computes[*]}"
  [ "$release" = yoga ] || echo "$BAG now says release $release (don't commit it); 'stage yoga' takes it out"
}

case "${1:-}" in
  stage)
    shift
    stage "$@"
    ;;
  jumphost)
    exec ssh -t "${SSH_OPTS[@]}" "almalinux@$(addr jumphost)" sudo tmux new -A -s upgrade
    ;;
  vms)
    run_on controller1 sudo /root/upgrade_vms.sh check
    ;;
  ssh)
    node=${2:?usage: $0 ssh <node> [cmd...]}
    shift 2
    exec ssh -t "${SSH_OPTS[@]}" "almalinux@$(addr "$node")" "$@"
    ;;
  nodes)
    for node in "${NODES[@]}"; do
      a=$(ip "$node")
      [ -z "$a" ] || printf '%-12s %s\n' "$node" "$a"
    done
    ;;
  *)
    usage
    exit 2
    ;;
esac
