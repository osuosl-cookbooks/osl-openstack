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

# Include missing package deps
%w(
  libvirt-python
  python-ethtool
  python-networking-mlnx
).each do |p|
  package p
end

include_recipe 'openstack-network::plugin_config'

service 'neutron-plugin-mlnx-agent' do
  service_name 'neutron-mlnx-agent'
  supports status: true, restart: true
  action [:enable, :start]
  subscribes :restart, ['template[/etc/neutron/neutron.conf]',
                        'template[/etc/neutron/plugins/mlnx/mlnx_conf.ini]']
end

service 'neutron-eswitchd' do
  service_name 'eswitchd'
  supports status: true, restart: true
  action [:enable, :start]
  subscribes :restart, ['template[/etc/neutron/neutron.conf]',
                        'template[/etc/neutron/plugins/ml2/eswitchd.conf]']
end
