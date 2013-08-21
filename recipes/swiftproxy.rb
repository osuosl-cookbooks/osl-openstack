# Include the umbrella packstack recipe
include_recipe "osl-packstack::default"

#### NOTICE: This doesn't install swift, it just installs swift proxy ,which is configured through packstack

# Install the Swift Proxy package
package "openstack-swift-proxy" do
  action :install
end
