#
# Cookbook:: osl-openstack
# Recipe:: ml2_mlnx
#
# Copyright:: 2017, Oregon State University
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
node.default['osl-openstack']['ml2_mlnx']['enabled'] = true

include_recipe 'osl-openstack'
include_recipe 'openstack-network::ml2_core_plugin'
include_recipe 'openstack-network'
include_recipe 'base::oslrepo'

yum_repository 'mellanox-ofed' do
  description 'Mellanox OFED'
  gpgkey 'http://packages.osuosl.org/repositories/centos-$releasever/mellanox-ofed/RPM-GPG-KEY-Mellanox'
  url "http://packages.osuosl.org/repositories/#{node['platform']}-$releasever/mellanox-ofed/$basearch"
end

# Include missing package deps
%w(
  mlnx-ofed-hypervisor
  mlnx-fw-updater
  libvirt-python
  python-ethtool
  python-networking-mlnx
).each do |p|
  package p
end

kernel_module 'mlx4_core' do
  onboot true
  reload false
  options %w(port_type_array=2 num_vfs=8 probe_vf=8 log_num_mgm_entry_size=-1 debug_level=1)
  notifies :restart, 'service[openibd]'
end

service 'openibd' do
  supports status: true, restart: true
  action [:enable, :start]
end

include_recipe 'openstack-network::plugin_config'

service 'neutron-plugin-mlnx-agent' do
  service_name 'neutron-mlnx-agent'
  supports status: true, restart: true
  action [:enable, :start]
  subscribes :restart, ['template[/etc/neutron/neutron.conf]',
                        'template[/etc/neutron/plugins/mlnx/mlnx_conf.ini]']
end
