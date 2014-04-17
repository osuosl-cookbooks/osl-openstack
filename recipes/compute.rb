#
# Cookbook Name:: osl-openstack
# Recipe:: compute
#
# Copyright 2013, Oregon State University
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

include_recipe "osl-openstack"

# Ensure nova is installed
yum_package  "openstack-nova" do
  action :install
  flush_cache [:before]
end

# Setup the nova user dir for ssh, for non-live migration/rresizing operations
directory "/var/lib/nova/.ssh" do
  owner "nova"
  group "nova"
  action :create
end

# Copy the ssh config to the nova user, change normal persm, not SELinux perms
template "/var/lib/nova/.ssh/config" do
  source "libvirtd-ssh-config.erb"
  owner "nova"
  group "nova"
  mode "700"
end

# Setup nova's private ssh key
ssh_key = Chef::EncryptedDataBagItem.load("ssh-keys", "openstack-nova")

template "/var/lib/nova/.ssh/id_rsa" do
  variables({:key => ssh_key['id_rsa']})
  owner "nova"
  mode 0600
  source "id_rsa.erb"
end

template "/var/lib/nova/.ssh/id_rsa.pub" do
  variables({:pub_key => ssh_key['id_rsa.pub']})
  owner "nova"
  mode 0644
  source "id_rsapub.erb"
end

template "/var/lib/nova/.ssh/authorized_keys" do
  variables({:pub_key => ssh_key['id_rsa.pub']})
  owner "nova"
  mode 0600
  source "id_rsapub.erb"
end
