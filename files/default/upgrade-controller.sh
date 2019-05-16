#!/bin/bash
# Steps taken primarily from https://www.rdoproject.org/install/upgrading-rdo-2/
# Specifically from this version for Newton https://git.io/vQGev

source /root/openrc

set -ex

# Disable Chef temporarily
rm -f /etc/cron.d/chef-client

# Change admin URL to port 5000
KEYSTONE_URL="$(openstack endpoint list --service keystone --interface public -c URL -f value)"
KEYSTONE_ADMIN_ID="$(openstack endpoint list --service keystone --interface admin -c ID -f value)"
openstack endpoint set --url $KEYSTONE_URL $KEYSTONE_ADMIN_ID

# Stop all OpenStack services
systemctl stop 'openstack-*'
systemctl stop 'neutron-*'
yum -y upgrade openstack-selinux
systemctl stop httpd

# Upgrade Keystone
yum -d1 -y upgrade \*keystone\* python2-oslo-config
yum -d1 -y upgrade \*horizon\*
keystone-manage token_flush
su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
systemctl start httpd

# Upgrade Glance
systemctl stop '*glance*'
yum -d1 -y upgrade \*glance\*
su -s /bin/sh -c "glance-manage db_sync" glance

# Upgrade Cinder
systemctl stop '*cinder*'
yum -d1 -y upgrade \*cinder\*
su -s /bin/sh -c "cinder-manage db sync" cinder

# Upgrade Heat
systemctl stop '*heat*'
# Removed by upstream
systemctl disable openstack-heat-api-cloudwatch
yum -d1 -y upgrade \*heat\*
su -s /bin/sh -c "heat-manage db_sync" heat

# Upgrade Ceilometer
systemctl stop '*ceilometer*'
systemctl stop '*aodh*'
systemctl stop '*gnocchi*'
# Removed by upstream
systemctl disable openstack-ceilometer-collector
yum -d1 -y upgrade \*ceilometer\* \*aodh\* \*gnocchi\*
set +e
ceilometer-upgrade --skip-gnocchi-resource-types --config-file /etc/ceilometer/ceilometer.conf
set -e

# Upgrade nova
crudini --set /etc/nova/nova.conf upgrade_levels compute auto
systemctl stop '*nova*'
# These were converted to wsgi
systemctl disable openstack-nova-api openstack-nova-metadata-api
yum -d1 -y upgrade \*nova\*
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
yum -d1 -y upgrade \*neutron\*
su -s /bin/sh -c "neutron-db-manage upgrade heads" neutron

# Fix EPEL dependency issue from Pike
yum -y remove python-django
yum -y install openstack-dashboard
# Upgrade the rest of the packages
yum -y upgrade

rm -f /root/nova-cell-db-uri
touch /root/queens-upgrade-done
