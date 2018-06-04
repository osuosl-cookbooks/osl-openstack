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
node.default['ceph']['config-sections'].tap do |conf|
  conf['client']['admin socket'] = '/var/run/ceph/guests/$cluster-$type.$id.$pid.$cctid.asok'
  conf['client']['rbd concurrent management ops'] = 20
  conf['client']['rbd cache'] = 'true'
  conf['client']['rbd cache writethrough until flush'] = 'true'
  conf['client']['log file'] = '/var/log/ceph/qemu-guest-$pid.log'
end

include_recipe 'firewall'
include_recipe 'firewall::openstack'
include_recipe 'firewall::vnc'
include_recipe 'osl-openstack::default'
include_recipe 'ibm-power::default'

kernel_module 'tun'

case node['kernel']['machine']
when 'ppc64le'
  node.default['base']['grub']['cmdline'] << %w(kvm_cma_resv_ratio=15)
  include_recipe 'chef-sugar::default'
  include_recipe 'yum-kernel-osuosl'
  include_recipe 'base::grub'

  package 'kernel-osuosl'

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
when 'x86_64'
  kernel_module 'kvm_intel' do
    onboot true
    reload false
    options %w(nested=1)
    check_availability true
    only_if { node.deep_fetch('dmi', 'processor', 'Manufacturer') == 'Intel(R) Corporation' }
  end
  kernel_module 'kvm_amd' do
    onboot true
    reload false
    options %w(nested=1)
    check_availability true
    only_if { node.deep_fetch('dmi', 'processor', 'Manufacturer') == 'AMD' }
  end
end

include_recipe 'osl-openstack::linuxbridge'
include_recipe 'openstack-compute::compute'
include_recipe 'openstack-telemetry::agent-compute'

if node['osl-openstack']['ceph']
  %w(
    /var/run/ceph/guests
    /var/log/ceph
  ).each do |d|
    directory d do
      owner 'qemu'
      group 'libvirt'
    end
  end

  include_recipe 'osl-openstack::_block_ceph'

  group 'ceph' do
    append true
    members %w(nova qemu)
    action :modify
    notifies :restart, 'service[nova-compute]', :immediately
  end

  secrets = openstack_credential_secrets
  secret_uuid = node['ceph']['fsid-secret']
  ceph_user = node['osl-openstack']['block']['rbd_store_user']
  secret_file = ::File.join(Chef::Config[:file_cache_path], 'secret.xml')

  template secret_file do
    source 'secret.xml.erb'
    user 'root'
    group 'root'
    mode '00600'
    variables(
      uuid: secret_uuid,
      client_name: ceph_user
    )
    not_if "virsh secret-list | grep #{secret_uuid}"
    not_if { secret_uuid.nil? }
  end

  execute "virsh secret-define --file #{secret_file}" do
    not_if "virsh secret-list | grep #{secret_uuid}"
    not_if { secret_uuid.nil? }
  end

  # this will update the key if necessary
  execute 'update virsh ceph secret' do
    command "virsh secret-set-value --secret #{secret_uuid} --base64 #{secrets['ceph']['block_token']}"
    sensitive true
    not_if "virsh secret-get-value #{secret_uuid} | grep #{secrets['ceph']['block_token']}"
    not_if { secret_uuid.nil? || secrets['ceph']['block_token'].nil? }
  end

  file secret_file do
    action :delete
  end
end

template '/etc/sysconfig/libvirt-guests' do
  variables(libvirt_guests: node['osl-openstack']['libvirt_guests'])
end

service 'libvirt-guests' do
  action [:enable, :start]
end

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

package 'libguestfs-tools'
