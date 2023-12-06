#!/bin/bash
# Steps taken primarily from https://www.rdoproject.org/install/upgrading-rdo-2/
# Specifically from this version for Newton https://git.io/vQGev

set -ex

# Disable Chef temporarily
rm -f /etc/cron.d/chef-client

# Stop all OpenStack services
systemctl stop 'openstack-*'
systemctl stop 'neutron-*'

# Upgrade the packages
yum -y upgrade

set +ex

touch /root/train-upgrade-done

echo
echo "Run the following command once the controller has been upgraded:"
echo "  cinc-client"
