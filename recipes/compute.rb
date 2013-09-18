#
# Cookbook Name:: osl-packstack
# Recipe:: compute
#
# Copyright 2013, Geoffrey Corey
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

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

# Setup nova's private ssh key
secret = Chef::EncryptedDataBagItem.load_secret(node['osl-packstack']['secret_file'])
ssh_key = Chef::EncryptedDataBagItem.load("ssh-keys", "packstack-nova", secret)

template "/var/lib/nova/.ssh/id_rsa" do
  variables(:key => ssh_key['id_rsa'])
  owner "nova"
  mode "600"
  source "id_rsa.erb"
end

template "/var/lib/nova/.ssh/id_rsa.pub" do
  variables(:pub_key => ssh_key['id_rsa.pub'])
  owner "nova"
  mode "644"
  source "id_rsapub.erb"
end

## TODO: Conver teh ssh key deployment to a more dynamic cookbook
