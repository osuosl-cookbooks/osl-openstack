# include the umbrella packastack recipe
include_recipe "osl-packstack::default"

##### NOTICE: This installs ONLY the nova compute package and configures libvirt for live migration. This does not setup any networking

# Ensure a few packages are installed
%{libvirt libvirt-client libvirt-python openstack-nova-compute}.each do |pkg|
  package pkg
    action :install
end

# libvirtd template stuff
#Source: https://github.com/opscode-cookbooks/nova/blob/master/recipes/libvirt.rb
template "/etc/libvirt/libvirtd.conf" do
  source "libvirtd.conf.erb"
  owner "root"
  group "root"
  mode "0644"
end # Don't need to start the service, as packstack will automatically do that

template "/etc/sysconfig/libvirtd" do
  source "libvirtd.erb"
  owner "root"
  group "root"
  mode "0644"
end # Don't need to start the service, as packstack will automatically do that
