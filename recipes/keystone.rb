
# Include the umbrella packstack recipe
include_recipe "osl-packstack::default"


# Install keystone stuff
%{openstack-keystone python-keystone python-keystoneclient}.each do |pkg|
  package pkg do
    action :install
  end
end
