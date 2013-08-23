# Include the umbrella packstack recipe
include_recipe "osl-packstack::default"

#### NOTICE: This doesn't install the nova compute package. That is only for an explicit compute node.

# Install nova and supporting packages
%w{openstack-nova-api openstack-nova-cert openstack-nova-common openstack-nova-conductor openstack-nova-console openstack-nova-network openstack-nova-novncproxy openstack-nova-scheduler python-nova python-novaclient}.each do |pkg|
  package pkg do
    action :install
  end
end
