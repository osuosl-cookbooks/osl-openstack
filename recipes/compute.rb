#
# Cookbook Name:: osl-openstack
# Recipe:: compute
#
# Copyright (C) 2014, 2015 Oregon State University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
include_recipe 'firewall'
include_recipe 'firewall::openstack'
include_recipe 'firewall::vnc'
include_recipe 'osl-openstack::default'
include_recipe 'ibm-power::default'

kernel_module 'tun'

case node['kernel']['machine']
when 'ppc64le'
  include_recipe 'chef-sugar::default'
  if %w(openstack).include?(node.deep_fetch('cloud', 'provider'))
    kernel_module 'kvm_pr'
  else
    kernel_module 'kvm_hv'
  end

  # Turn off smt on boot (required for KVM support)
  # NOTE: This really should be handled via an rclocal cookbook
  cookbook_file '/etc/rc.d/rc.local' do
    owner 'root'
    group 'root'
    mode 0755
  end

  # Turn off smt during runtime
  execute 'ppc64_cpu_smt_off' do
    command '/sbin/ppc64_cpu --smt=off'
    not_if '/sbin/ppc64_cpu --smt 2>&1 | ' \
      'grep -E \'SMT is off|Machine is not SMT capable\''
  end
end

include_recipe 'osl-openstack::linuxbridge'
include_recipe 'openstack-compute::compute'
include_recipe 'openstack-telemetry::agent-compute'

# Not needed on a compute node
delete_resource(:directory, '/var/run/httpd/ceilometer')

# Setup ssh key for nova migrations between compute nodes
user_account 'nova' do
  system_user true
  home '/var/lib/nova'
  comment 'OpenStack Nova Daemons'
  uid 162
  gid 162
  shell '/bin/sh'
  manage_home false
  ssh_keygen false
  ssh_keys [node['osl-openstack']['nova_public_key']]
end

nova_key = data_bag_item(
  "#{node['osl-openstack']['databag_prefix']}_secrets",
  'nova_migration_key'
)

file '/var/lib/nova/.ssh/id_rsa' do
  content nova_key['nova_migration_key']
  sensitive true
  user 'nova'
  group 'nova'
  mode 0600
end

file '/var/lib/nova/.ssh/config' do
  content <<-EOL
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  EOL
  user 'nova'
  group 'nova'
  mode 0600
end
