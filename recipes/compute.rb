##### NOTICE: This installs ONLY the nova compute package and configures libvirt for live migration. This does not setup any networking

# Ensure a few packages are installed
%w{libvirt libvirt-client libvirt-python openstack-nova-compute}.each do |pkg|
  package pkg do
    action :install
  end
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


# Setup the nova user dir for ssh, for non-live migration/rresizing operations
directory "/var/lib/nova/.ssh" do
  owner "nova"
  group "nova"
  action :create
end

# Enable the nova user to have a login
execute "enable nova login" do
  command "usermod -s /bin/bash nova"
end

# Copy the ssh config to the nova user, change normal persm, not SELinux perms
template "/var/lib/nova/.ssh/config" do
  source "libvirtd-ssh-config.erb"
  owner "nova"
  group "nova"
  mode "700"
end

## TODO: get the ssh private key.
