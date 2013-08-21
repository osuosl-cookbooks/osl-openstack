# Include the umbrella packstack recipe
include_recipe "osl-packstack::default"


# Install Swift and supporting packages
%{openstack-swift openstac-swift-account openstack-swift-container openstack-swift-object openstack-swift-plugin-swift3}.each do |pkg|
  package pkg do
   action :install
  end
end
