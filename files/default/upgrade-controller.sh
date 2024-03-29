#!/bin/bash
# Steps taken primarily from https://www.rdoproject.org/install/upgrading-rdo-2/
# Specifically from this version for Newton https://git.io/vQGev

source /root/openrc

set -ex

# Disable Chef temporarily
rm -f /etc/cron.d/chef-client

# Stop all OpenStack services
systemctl stop 'openstack-*'
systemctl stop 'neutron-*'
yum -y upgrade openstack-selinux
systemctl stop httpd

# Upgrade Keystone
yum -y upgrade \*keystone\*
yum -y upgrade \*horizon\*
su -s /bin/sh -c "keystone-manage db_sync" keystone
systemctl start httpd

# Upgrade Glance
systemctl stop '*glance*'
yum -y upgrade \*glance\*
su -s /bin/sh -c "glance-manage db_sync" glance

# Upgrade Cinder
systemctl stop '*cinder*'
yum -y upgrade \*cinder\*
su -s /bin/sh -c "cinder-manage db sync" cinder
su -s /bin/sh -c "cinder-manage db online_data_migrations" cinder

# Upgrade Heat
systemctl stop '*heat*'
yum -y upgrade \*heat\*
su -s /bin/sh -c "heat-manage db_sync" heat

# Upgrade Ceilometer
systemctl stop '*ceilometer*'
yum -y upgrade \*ceilometer\*

# Upgrade nova
crudini --set /etc/nova/nova.conf upgrade_levels compute auto
systemctl stop '*nova*'
systemctl disable openstack-nova-consoleauth
yum -y upgrade \*nova\*
cell_db_uri=$(cat /root/nova-cell-db-uri)
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage db online_data_migrations" nova
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts" nova
cell1_uuid=$(nova-manage cell_v2 list_cells | grep cell1 | awk '{print $4}')
su -s /bin/sh -c "nova-manage cell_v2 map_instances --cell_uuid ${cell1_uuid}" nova
crudini --del /etc/nova/nova.conf upgrade_levels compute

# Upgrade neutron
systemctl stop '*neutron*'
yum -y upgrade \*neutron\*
su -s /bin/sh -c "neutron-db-manage upgrade heads" neutron

# Upgrade the rest of the packages
yum -y upgrade

rm -f /root/nova-cell-db-uri
touch /root/train-upgrade-done
