#!/bin/bash
# Steps taken primarily from https://www.rdoproject.org/install/upgrading-rdo-2/
# Specifically from this version for Newton https://git.io/vQGev

set -ex

# Disable Chef temporarily
rm -f /etc/cron.d/chef-client

# Stop and disable openstack-ceilometer-api.service as it will be served via
# httpd now
systemctl stop openstack-ceilometer-api
systemctl disable openstack-ceilometer-api

# Stop all OpenStack services
systemctl snapshot openstack-services
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
systemctl start openstack-glance-api \
  openstack-glance-registry

# Upgrade Cinder
systemctl stop '*cinder*'
yum -d1 -y upgrade \*cinder\* python2-os-brick
su -s /bin/sh -c "cinder-manage db sync" cinder
systemctl start openstack-cinder-api \
  openstack-cinder-scheduler \
  openstack-cinder-volume

# Upgrade Ceilometer
systemctl stop '*ceilometer*'
yum -d1 -y upgrade \*ceilometer\* \*aodh\* \*gnocchi\*
ceilometer-dbsync
systemctl start openstack-ceilometer-central \
  openstack-ceilometer-collector \
  openstack-ceilometer-notification

# ceilometer-api

# Upgrade nova
crudini --set /etc/nova/nova.conf upgrade_levels compute mitaka
systemctl stop '*nova*'
yum -d1 -y upgrade \*nova\*
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage db online_data_migrations" nova
crudini --del /etc/nova/nova.conf upgrade_levels compute
systemctl start openstack-nova-api \
  openstack-nova-conductor \
  openstack-nova-consoleauth \
  openstack-nova-novncproxy \
  openstack-nova-scheduler

# Upgrade neutron
systemctl stop '*neutron*'
yum -d1 -y upgrade \*neutron\* python-pecan
su -s /bin/sh -c "neutron-db-manage upgrade heads" neutron
systemctl start neutron-dhcp-agent \
  neutron-l3-agent \
  neutron-metadata-agent \
  neutron-linuxbridge-agent \
  neutron-server

# Upgrade the rest of the packages
yum -y upgrade

# Restart all OpenStack services
systemctl isolate openstack-services.snapshot
