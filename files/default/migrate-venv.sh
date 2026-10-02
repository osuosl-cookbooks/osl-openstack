#!/bin/bash
# Swap this node's RDO OpenStack packages for the osuosl-openstack venv RPMs in
# one dnf transaction. Run cinc-client afterwards to render configs and start services.
set -Eeuo pipefail

stamp="$(date +%Y%m%d%H%M%S)"
logfile="/root/migrate-venv-${stamp}.log"
exec > >(tee -a "${logfile}") 2>&1

# Timestamped to the log file and the terminal, and the step markers to journald
log() {
    printf '%s migrate-venv: %s\n' "$(date -Is)" "$*"
    logger -t migrate-venv -- "$*" 2>/dev/null || true
}
trap 'log "FAILED at line ${LINENO}: ${BASH_COMMAND}"' ERR

log "starting on $(hostname -f), logging to ${logfile}"

# The gated cinc-client run writes the venv repo before stopping
if [[ -z "$(dnf -q repoquery osuosl-openstack-cli 2>/dev/null)" ]]; then
    log "osuosl-openstack-cli is not available from any enabled repo; run cinc-client first"
    exit 1
fi
log "osuosl-openstack-cli is available"

# Keep scheduled Chef runs out of the way; cinc-client restores this
log "removing /etc/cron.d/chef-client"
rm -fv /etc/cron.d/chef-client

# RDO package -> osuosl-openstack package that replaces it
declare -A replaces=(
    [openstack-ceilometer-common]=ceilometer
    [openstack-cinder]=cinder
    [openstack-dashboard]=horizon
    [openstack-glance]=glance
    [openstack-heat-common]=heat
    [openstack-keystone]=keystone
    [openstack-neutron]=neutron-controller
    [openstack-neutron-linuxbridge]=neutron-agent
    [openstack-nova-api]=nova-controller
    [openstack-nova-compute]=nova-compute
    [openstack-placement-api]=placement
)
pkgs=(osuosl-openstack-cli)
for rdo in "${!replaces[@]}"; do
    if rpm -q --quiet "${rdo}"; then
        pkgs+=("osuosl-openstack-${replaces[${rdo}]}")
    fi
done
mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
log "packages to install: ${pkgs[*]}"

rpmlist="/root/pre-venv-rpms-${stamp}.txt"
etctar="/root/pre-venv-etc-${stamp}.tgz"
unitlist="/root/pre-venv-units-${stamp}.txt"
userlist="/root/pre-venv-userinstalled-${stamp}.txt"
rpm -qa | sort > "${rpmlist}"
# dnf history undo reinstalls the swapped-out packages as dependencies
dnf -q repoquery --userinstalled --qf '%{name}' 2>/dev/null | sort -u > "${userlist}"
log "saved the $(wc -l < "${userlist}") user-installed package names to ${userlist}"
etc_dirs=()
for d in ceilometer cinder glance heat httpd keystone neutron nova openstack-dashboard placement; do
    if [[ -d "/etc/${d}" ]]; then
        etc_dirs+=("/etc/${d}")
    fi
done
# A client-only node has none of these
if (( ${#etc_dirs[@]} )); then
    tar czf "${etctar}" -C / "${etc_dirs[@]#/}"
    log "saved ${rpmlist} and ${etctar}"
else
    log "saved ${rpmlist}; no service /etc dirs to archive"
fi

# RDO's %preun disables its units, which share names with ours, until cinc-client
units=('openstack-*' 'neutron-*' 'httpd.service')
{
    echo "# enabled"
    systemctl list-unit-files --no-legend --state=enabled "${units[@]}" || true
    echo "# active"
    systemctl list-units --no-legend --plain --state=active "${units[@]}" || true
} > "${unitlist}"
mapfile -t active < <(systemctl list-units --no-legend --plain --state=active "${units[@]}" | awk '{ print $1 }' || true)
log "saved ${unitlist}: ${#active[@]} active units"

log "stopping: ${active[*]}"
systemctl stop 'openstack-*' 'neutron-*'
if systemctl is-active --quiet httpd; then
    systemctl stop httpd
fi

# Keep RDO's logs now the services are stopped: dnf deletes keystone.log with
# openstack-keystone, and the venv services log to journald instead
logtar="/root/pre-venv-logs-${stamp}.tgz"
log_dirs=()
for d in ceilometer cinder glance heat keystone neutron nova placement; do
    if [[ -d "/var/log/${d}" ]]; then
        log_dirs+=("/var/log/${d}")
    fi
done
if (( ${#log_dirs[@]} )); then
    if tar czf "${logtar}" -C / "${log_dirs[@]#/}"; then
        log "saved ${logtar} ($(du -h "${logtar}" | cut -f1))"
    else
        log "WARNING: could not archive the service logs to ${logtar}; continuing"
    fi
fi

# Read all of dnf's output: exiting early breaks its pipe and trips pipefail
last_txn() { dnf history list 2>/dev/null | awk 'NR > 2 && $1 ~ /^[0-9]+$/ && !id { id = $1 } END { print id }'; }

# The APIs run under uWSGI now, so mod_wsgi goes in the same transaction
txnfile="/root/migrate-venv-${stamp}.dnf"
{
    echo "install ${pkgs[*]}"
    if rpm -q --quiet python3-mod_wsgi; then
        echo "remove python3-mod_wsgi"
    fi
    echo "run"
} > "${txnfile}"

# Interactive on purpose: review what is removed and installed before answering y.
# dnf shell exits 0 even when the answer is no, so compare history ids instead
before="$(last_txn)"
log "running dnf --allowerasing shell ${txnfile}; review the transaction"
dnf --allowerasing shell "${txnfile}" || true
txn="$(last_txn)"
if [[ "${txn}" == "${before}" ]] || ! rpm -q --quiet osuosl-openstack-cli; then
    log "dnf did not complete; nothing was swapped, starting the stopped units again"
    if (( ${#active[@]} )); then
        systemctl start "${active[@]}"
    fi
    exit 1
fi
log "swapped to: ${pkgs[*]} (dnf history ${txn})"

# Chef enabled mod_wsgi; httpd would fail on its LoadModule once the .so is gone
if ! rpm -q --quiet python3-mod_wsgi; then
    for f in /etc/httpd/mods-enabled/wsgi.load /etc/httpd/mods-enabled/wsgi.conf \
             /etc/httpd/mods-available/wsgi.load /etc/httpd/mods-available/wsgi_python3.load; do
        if [[ -e "${f}" || -L "${f}" ]]; then
            rm -f "${f}"
            log "removed ${f}"
        fi
    done
    # Likewise on the vhosts still using WSGI directives; cinc-client re-renders
    # them for uWSGI and enables them again
    for f in /etc/httpd/sites-enabled/* /etc/httpd/conf-enabled/*; do
        if [[ -L "${f}" ]] && grep -qE '^\s*WSGI' "${f}" 2>/dev/null; then
            rm -f "${f}"
            log "disabled ${f}: it used mod_wsgi"
        fi
    done
fi

mapfile -t rpmsave < <(find /etc -name '*.rpmsave' -newer "${rpmlist}")
if (( ${#rpmsave[@]} )); then
    log "RDO configs saved as .rpmsave, which cinc-client renders again:"
    printf '  %s\n' "${rpmsave[@]}"
fi

# RDO's network-scripts and OVS stay; as user-installed they hold their deps
# (openvswitch, initscripts, chkconfig) through the cleanup below
keep_re='^(openstack-network-scripts.*|rdo-openvswitch|python3-rdo-openvswitch)$'
mapfile -t protect < <(rpm -qa --qf '%{NAME}\n' | grep -E "${keep_re}" || true)
if (( ${#protect[@]} )); then
    dnf -q mark install "${protect[@]}"
    log "marked as user-installed, so the cleanup keeps them: ${protect[*]}"
fi

# RDO's leftover libraries, minus any that a package outside the set still needs.
# rpm -e --test only reports; dnf resolves rich deps. Repeat until stable
in_set() { printf '%s\n' "${members[@]}" | grep -qxF "$1"; }
mapfile -t members < <(
    dnf -q repoquery --installed --qf '%{name} %{from_repo}' 2>/dev/null |
        awk '$2 == "RDO-openstack" { print $1 }' | grep -vE "${keep_re}" | sort || true
)
rdo_total="${#members[@]}"
for _ in {1..20}; do
    (( ${#members[@]} )) || break
    mapfile -t keep < <(
        { rpm -e --test "${members[@]}" 2>&1 || true; } |
            awk '/is needed by \(installed\)/ { print $NF }' | sort -u |
            while read -r by; do
                in_set "$(rpm -q --qf '%{NAME}' "${by}")" && continue
                dnf -q repoquery --installed --requires --resolve --qf '%{name}' "${by}" 2>/dev/null || true
            done | sort -u | while read -r p; do
                if in_set "${p}"; then echo "${p}"; fi
            done
    )
    (( ${#keep[@]} )) || break
    mapfile -t members < <(printf '%s\n' "${members[@]}" | grep -vxF -f <(printf '%s\n' "${keep[@]}") || true)
done
cleanup="/root/pre-venv-cleanup-${stamp}.txt"
if (( ${#members[@]} )); then printf '%s\n' "${members[@]}"; fi > "${cleanup}"
log "RDO leftovers: ${#members[@]} of ${rdo_total} removable, the rest still needed (${cleanup})"

ctxn=""
if (( ${#members[@]} )); then
    # dnf also removes the dependencies only these pulled in
    log "running dnf remove on the ${#members[@]} packages and what they pulled in; review the transaction"
    cbefore="$(last_txn)"
    dnf remove "${members[@]}" || true
    if [[ "$(last_txn)" != "${cbefore}" ]]; then
        ctxn="$(last_txn)"
        log "removed the RDO leftovers (dnf history ${ctxn})"
    else
        log "RDO leftovers kept; the node is fine, remove them later with: dnf remove \$(cat ${cleanup})"
    fi
fi
mapfile -t unneeded < <(dnf -q repoquery --unneeded --qf '%{name}' 2>/dev/null || true)
if (( ${#unneeded[@]} < 20 )); then
    log "dnf autoremove would now remove ${#unneeded[@]} packages: ${unneeded[*]}"
else
    log "dnf autoremove would now remove ${#unneeded[@]} packages; review with: dnf repoquery --unneeded"
fi

log "to roll back, in order:"
if [[ -n "${ctxn}" ]]; then
    echo "  dnf history undo ${ctxn}"
fi
echo "  dnf history undo ${txn}"
printf '  %s\n' "dnf mark install \$(comm -12 ${userlist} <(rpm -qa --qf '%{NAME}\n' | sort -u))"
log "now run cinc-client, then compare the units with ${unitlist}"
