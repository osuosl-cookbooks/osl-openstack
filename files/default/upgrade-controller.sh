#!/bin/bash
# Steps taken primarily from https://www.rdoproject.org/install/upgrading-rdo-2/
# Specifically from this version for Newton https://git.io/vQGev

source /root/openrc

set -ex

# Disable Chef temporarily
rm -f /etc/cron.d/chef-client

# Uprade this first since it takes so long
dnf -y upgrade openstack-selinux

# Stop all OpenStack services
systemctl stop 'openstack-*'
systemctl stop 'neutron-*'
systemctl stop httpd

# Upgrade Keystone
dnf -y upgrade \*keystone\*
dnf -y upgrade \*horizon\* \*django\*
su -s /bin/sh -c "keystone-manage db_sync" keystone
rm -rfv /usr/lib/systemd/system/httpd.service.d/openstack-dashboard.conf
systemctl daemon-reload
# Workaround issue with COMPRESS_PRECOMPILERS in horizon after the upgrade [1]
# [1] https://access.redhat.com/solutions/7011005
systemctl restart memcached
systemctl start httpd

# Upgrade Glance
systemctl stop '*glance*'
dnf -y upgrade \*glance\*
su -s /bin/sh -c "glance-manage db_sync" glance

# Upgrade Cinder
systemctl stop '*cinder*'
dnf -y upgrade \*cinder\*
su -s /bin/sh -c "cinder-manage db sync" cinder
su -s /bin/sh -c "cinder-manage db online_data_migrations" cinder

# Upgrade Heat
systemctl stop '*heat*'
dnf -y upgrade \*heat\*
su -s /bin/sh -c "heat-manage db_sync" heat

# Upgrade Ceilometer
systemctl stop '*ceilometer*'
dnf -y upgrade \*ceilometer\*

# Upgrade placement
dnf -y upgrade \*placement\* --best --allowerasing
su -s /bin/sh -c "placement-manage db sync" placement

# Upgrade nova
crudini --set /etc/nova/nova.conf upgrade_levels compute auto
systemctl stop '*nova*'
dnf -y upgrade \*nova\* --best --allowerasing
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage db online_data_migrations" nova
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts" nova
cell1_uuid=$(nova-manage cell_v2 list_cells | grep cell1 | awk '{print $4}')
su -s /bin/sh -c "nova-manage cell_v2 map_instances --cell_uuid ${cell1_uuid}" nova
crudini --del /etc/nova/nova.conf upgrade_levels compute

# Upgrade neutron
systemctl stop '*neutron*'
dnf -y upgrade \*neutron\*
su -s /bin/sh -c "neutron-db-manage upgrade heads" neutron

# Upgrade the rest of the packages
dnf -y upgrade --best --allowerasing

touch /root/xena-upgrade-done
