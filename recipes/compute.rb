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

osl_repos_openstack 'compute'
osl_openstack_client 'compute'
osl_firewall_openstack 'compute'
osl_firewall_vnc 'osl-openstack'

s = os_secrets
c = s['compute']
b = s['block-storage']

include_recipe 'yum-qemu-ev'

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
  action [:install, :load]
end

# Disable IPv6 autoconf globally
cookbook_file '/etc/sysconfig/network'

package %w(
  device-mapper
  device-mapper-multipath
  libguestfs-rescue
  libguestfs-tools
  libvirt
  openstack-nova-compute
  python-libguestfs
  sg3_utils
  sysfsutils
)

link "/usr/bin/qemu-system-#{node['kernel']['machine']}" do
  to '/usr/libexec/qemu-kvm'
end

cookbook_file '/etc/libvirt/libvirtd.conf' do
  notifies :restart, 'service[libvirtd]'
end

service 'libvirtd' do
  action [:enable, :start]
end

execute 'Deleting default libvirt network' do
  command 'virsh net-destroy default'
  only_if 'virsh net-list | grep -q default'
end

include_recipe 'osl-openstack::compute_common'

service 'openstack-nova-compute' do
  action [:enable, :start]
  subscribes :restart, 'template[/etc/nova/nova.conf]'
end

service 'libvirt-guests' do
  action [:enable, :start]
end

case node['kernel']['machine']
when 'ppc64le'
  node.default['base']['grub']['cmdline'] << %w(kvm_cma_resv_ratio=15)
  include_recipe 'yum-kernel-osuosl::install'
  include_recipe 'base::grub'

  kernel_module 'kvm_pr' do
    action [:install, :load]
    only_if 'lscpu | grep "KVM"'
  end

  kernel_module 'kvm_hv' do
    action [:install, :load]
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
  end if node.read('cpu', 'cpu_model') =~ /POWER8/
when 'aarch64'
  include_recipe 'yum-kernel-osuosl::install'
  include_recipe 'base::grub'
when 'x86_64'
  kvm_module =
    if node.read('dmi', 'processor', 'manufacturer') == 'AMD'
      'kvm_amd'
    else
      'kvm_intel'
    end

  kernel_module kvm_module do
    options %w(nested=1)
    action [:install, :load]
  end
end

include_recipe 'osl-openstack::network'
include_recipe 'osl-openstack::telemetry_compute'

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
    notifies :restart, 'service[openstack-nova-compute]', :immediately
    notifies :restart, 'service[libvirtd]', :immediately
  end

  ceph_user = b['ceph']['rbd_store_user']
  secret_file = ::File.join(Chef::Config[:file_cache_path], 'secret.xml')

  template secret_file do
    source 'secret.xml.erb'
    user 'root'
    group 'root'
    mode '00600'
    variables(
      uuid: ceph_fsid,
      client_name: ceph_user
    )
    not_if "virsh secret-list | grep #{ceph_fsid}"
    not_if { ceph_fsid.nil? }
  end

  execute "virsh secret-define --file #{secret_file}" do
    not_if "virsh secret-list | grep #{ceph_fsid}"
    not_if { ceph_fsid.nil? }
  end

  # this will update the key if necessary
  execute 'update virsh ceph secret' do
    command "virsh secret-set-value --secret #{ceph_fsid} --base64 #{b['ceph']['block_token']}"
    sensitive true
    not_if "virsh secret-get-value #{ceph_fsid} | grep #{b['ceph']['block_token']}"
    not_if { b['ceph']['block_token'].nil? }
    not_if { ceph_fsid.nil? }
  end

  file secret_file do
    action :delete
  end
end

template '/etc/sysconfig/libvirt-guests' do
  variables(libvirt_guests: c['libvirt_guests'])
end

osl_authorized_keys 'nova_public_key' do
  user 'nova'
  key c['nova_public_key']
  dir_path '/var/lib/nova/.ssh'
end

osl_ssh_key 'nova_migration_key' do
  content c['nova_migration_key']
  key_name 'id_rsa'
  user 'nova'
  dir_path '/var/lib/nova/.ssh'
end

file '/var/lib/nova/.ssh/config' do
  content <<~EOL
    Host *
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
  EOL
  user 'nova'
  group 'nova'
  mode '600'
end
