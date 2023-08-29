#
# Cookbook:: osl-openstack
# Recipe:: compute
#
# Copyright:: 2014-2023, Oregon State University
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
osl_firewall_openstack 'osl-openstack'
osl_firewall_vnc 'osl-openstack'

include_recipe 'osl-openstack::default'
include_recipe 'ibm-power::default'

edit_resource(:osl_ceph_config, 'default') do
  client_options [
    'admin socket = /var/run/ceph/guests/$cluster-$type.$id.$pid.$cctid.asok',
    'rbd concurrent management ops = 20',
    'rbd cache = true',
    'rbd cache writethrough until flush = true',
    'log file = /var/log/ceph/qemu-guest-$pid.log',
  ]
end

kernel_module 'tun' do
  action :load
end

# Disable IPv6 autoconf globally
cookbook_file '/etc/sysconfig/network'

case node['kernel']['machine']
when 'ppc64le'
  node.default['base']['grub']['cmdline'] << %w(kvm_cma_resv_ratio=15)
  include_recipe 'yum-kernel-osuosl::install'
  include_recipe 'base::grub'

  kernel_module 'kvm_pr' do
    action :load
    only_if 'lscpu | grep "KVM"'
  end

  kernel_module 'kvm_hv' do
    action :load
    not_if 'lscpu | grep "KVM"'
  end

  # TODO: revert back to stock file now that we can use the systemd unit
  cookbook_file '/etc/rc.d/rc.local' do
    mode '644'
  end

  # SMT needs to be on POWER8 systems due to architecture limitations
  # (unit is part of the powerpc-utils package)
  service 'smt_off' do
    action [:enable, :start]
  end if node.read('ibm_power', 'cpu', 'cpu_model') =~ /power8/
when 'aarch64'
  include_recipe 'yum-kernel-osuosl::install'
  include_recipe 'base::grub'
when 'x86_64'
  kvm_module =
    if node.read('dmi', 'processor', 'manufacturer') == 'AMD'
      'kvm-amd'
    else
      'kvm-intel'
    end

  kernel_module kvm_module do
    options %w(nested=1)
    action [:install, :load]
  end
end

# Missing package dep for telemetry
package 'python2-wsme'

include_recipe 'osl-openstack::linuxbridge'
include_recipe 'openstack-compute::compute'
include_recipe 'openstack-telemetry::agent-compute'

delete_lines 'remove dhcpbridge on compute' do
  path '/usr/share/nova/nova-dist.conf'
  pattern '^dhcpbridge.*'
  backup true
  notifies :restart, 'service[nova-compute]'
end

delete_lines 'remove force_dhcp_release on compute' do
  path '/usr/share/nova/nova-dist.conf'
  pattern '^force_dhcp_release.*'
  backup true
  notifies :restart, 'service[nova-compute]'
end

# We still need the ceph keys if we're using it for cinder
include_recipe 'osl-openstack::_block_ceph' if node['osl-openstack']['ceph']['volume']

if node['osl-openstack']['ceph']['volume'] || node['osl-openstack']['ceph']['compute']
  %w(
    /var/run/ceph/guests
    /var/log/ceph
  ).each do |d|
    directory d do
      owner 'qemu'
      group 'libvirt'
    end
  end

  group 'ceph-compute' do
    group_name 'ceph'
    append true
    members %w(nova qemu)
    action :modify
    notifies :restart, 'service[nova-compute]', :immediately
    notifies :restart, 'service[libvirt-bin]', :immediately
  end

  secrets = openstack_credential_secrets
  fsid = ceph_fsid
  ceph_user = node['osl-openstack']['block']['rbd_store_user']
  secret_file = ::File.join(Chef::Config[:file_cache_path], 'secret.xml')

  template secret_file do
    source 'secret.xml.erb'
    user 'root'
    group 'root'
    mode '00600'
    variables(
      uuid: fsid,
      client_name: ceph_user
    )
    not_if "virsh secret-list | grep #{fsid}"
    not_if { fsid.nil? }
  end

  execute "virsh secret-define --file #{secret_file}" do
    not_if "virsh secret-list | grep #{fsid}"
    not_if { fsid.nil? }
  end

  # this will update the key if necessary
  execute 'update virsh ceph secret' do
    command "virsh secret-set-value --secret #{fsid} --base64 #{secrets['ceph']['block_token']}"
    sensitive true
    not_if "virsh secret-get-value #{fsid} | grep #{secrets['ceph']['block_token']}"
    not_if { secrets['ceph']['block_token'].nil? }
    not_if { fsid.nil? }
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
  mode '600'
end

file '/var/lib/nova/.ssh/config' do
  content <<-EOL
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  EOL
  user 'nova'
  group 'nova'
  mode '600'
end

package 'libguestfs-tools'

# TODO: Remove after rocky
# This is no longer needed
delete_resource(:execute, 'enable nova login')
