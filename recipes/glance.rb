
# include the umbrella packstack recipe
include_recipe "osl-packstack::default"


# Install Glance and supporting packages
%{openstack-glance python-glance python-glanceclient}.each do |pkg|
  package pkg do
    action :install
  end
end
