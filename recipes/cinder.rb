
# Include the umbrella packstack recipe
include_recipe "osl-packstack::default"


# Install Cinder and supporting packages
%{openstack-cinder python-cinder python-cinderclient}.each do |pkg|
  package pkg do
    action :install
  end
end
