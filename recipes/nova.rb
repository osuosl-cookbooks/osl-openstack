
# Ensure a few packages are installed
%{libvirt libvirt-client libvirt-python}.each do |pkg|
  package pkg
    action :install
end

# TODO: install the nova compute package, also yum update to get the rdo update (kernel, iproute, etc)

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
  only_if { platform?(%w{fedora redhat centos}) }
end # Don't need to start the service, as packstack will automatically do that
