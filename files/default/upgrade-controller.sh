#!/bin/bash
# Steps taken primarily from https://www.rdoproject.org/install/upgrading-rdo-2/
# Specifically from this version for Newton https://git.io/vQGev

set -ex

# Disable Chef temporarily
rm -f /etc/cron.d/chef-client

# Stop all OpenStack services
systemctl stop 'openstack-*'
systemctl stop 'neutron-*'
yum -y upgrade openstack-selinux
systemctl stop httpd

# Upgrade Keystone
yum -d1 -y upgrade \*keystone\*
yum -y upgrade \*horizon\* \*openstack-dashboard\*
yum -d1 -y upgrade \*horizon\* \*python-django\*
keystone-manage token_flush
su -s /bin/sh -c "keystone-manage db_sync" keystone
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
yum -d1 -y upgrade \*nova\*
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage db online_data_migrations" nova
crudini --del /etc/nova/nova.conf upgrade_levels compute

# Upgrade neutron
systemctl stop '*neutron*'
yum -d1 -y upgrade \*neutron\* python-pecan
su -s /bin/sh -c "neutron-db-manage upgrade heads" neutron

# Upgrade the rest of the packages
yum -y upgrade

touch /root/ocata-upgrade-done
