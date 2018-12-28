#!/bin/bash
# Steps taken primarily from https://www.rdoproject.org/install/upgrading-rdo-2/
# Specifically from this version for Newton https://git.io/vQGev

source /root/openrc

set -ex

# Disable Chef temporarily
rm -f /etc/cron.d/chef-client

# Remove nova-cert service as it's been deprecated
nova_cert_id="$(openstack compute service list -f value -c ID -c Binary | grep nova-cert | awk '{print $1}')"
openstack compute service delete $nova_cert_id

# Remove old keystone API endpoints (in this specific order)
for i in public internal admin ; do
  openstack endpoint list | grep -E "(Service|keystone)" | grep v2.0 | \
  grep $i | awk '{print $2}' | xargs -r -n 1 openstack endpoint delete
done

# Remove old nova API endpoints
openstack endpoint list | grep -E "(Service|nova)" | grep "v2\/" | \
  awk '{print $2}' | xargs -r -i openstack endpoint {}

# Stop all OpenStack services
systemctl stop 'openstack-*'
systemctl stop 'neutron-*'
yum -y upgrade openstack-selinux
systemctl stop httpd

# Upgrade Keystone
yum -d1 -y upgrade \*keystone\* python2-oslo-config
yum -d1 -y remove python-django-bash-completion
yum -d1 -y install \*horizon\* \*openstack-dashboard\*
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
yum -d1 -y upgrade \*heat\*
su -s /bin/sh -c "heat-manage db_sync" heat

# Upgrade Ceilometer
systemctl stop '*ceilometer*'
systemctl stop '*aodh*'
systemctl stop '*gnocchi*'
yum -d1 -y upgrade \*ceilometer\* \*aodh\* \*gnocchi\* python2-cotyledon
set +e
ceilometer-upgrade --skip-gnocchi-resource-types --config-file /etc/ceilometer/ceilometer.conf
set -e

# Upgrade nova
crudini --set /etc/nova/nova.conf upgrade_levels compute newton
systemctl stop '*nova*'
systemctl disable openstack-nova-cert
yum remove -y openstack-nova-cert
yum -d1 -y upgrade \*nova\*
cell_db_uri=$(cat /root/nova-cell-db-uri)
su -s /bin/sh -c "nova-manage cell_v2 map_cell0 --database_connection ${cell_db_uri}" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --verbose --name cell1" nova
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage db online_data_migrations" nova
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts" nova
cell1_uuid=$(nova-manage cell_v2 list_cells | grep cell1 | awk '{print $4}')
su -s /bin/sh -c "nova-manage cell_v2 map_instances --cell_uuid ${cell1_uuid}" nova
crudini --del /etc/nova/nova.conf upgrade_levels compute

# Upgrade neutron
systemctl stop '*neutron*'
yum -d1 -y upgrade \*neutron\* python-pecan
su -s /bin/sh -c "neutron-db-manage upgrade heads" neutron

# Upgrade the rest of the packages
yum -y upgrade

rm -f /root/nova-cell-db-uri
touch /root/ocata-upgrade-done
