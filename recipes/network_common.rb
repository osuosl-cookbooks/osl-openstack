#
# Cookbook:: osl-openstack
# Recipe:: network_common
#
# Copyright:: 2023-2024, Oregon State University
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

s = os_secrets
n = s['network']
auth_endpoint = s['identity']['endpoint']
controller = node['osl-openstack']['node_type'] == 'controller'

template '/etc/neutron/neutron.conf' do
  owner 'root'
  group 'neutron'
  mode '0640'
  sensitive true
  variables(
    auth_endpoint: auth_endpoint,
    compute_pass: s['compute']['service']['pass'],
    controller: controller,
    database_connection: openstack_database_connection('network'),
    memcached_endpoint: s['memcached']['endpoint'],
    region: n['region'],
    service_pass: n['service']['pass'],
    transport_url: openstack_transport_url
  )
end

cookbook_file '/etc/neutron/plugins/ml2/ml2_conf.ini' do
  owner 'root'
  group 'neutron'
  mode '0640'
end

link '/etc/neutron/plugin.ini' do
  to '/etc/neutron/plugins/ml2/ml2_conf.ini'
end

osl_systemd_unit_drop_in 'part_of_iptables' do
  extend Iptables::Cookbook::Helpers
  content({
    'Unit' => {
      'PartOf' => "#{get_service_name(:ipv4)}.service",
    },
  })
  unit_name 'neutron-linuxbridge-agent.service'
end

template '/etc/neutron/plugins/ml2/linuxbridge_agent.ini' do
  owner 'root'
  group 'neutron'
  mode '0640'
  variables(
    local_ip: openstack_vxlan_ip(controller),
    physical_interface_mappings: openstack_physical_interface_mappings(controller)
  )
  notifies :restart, 'service[neutron-linuxbridge-agent]'
end

service 'neutron-linuxbridge-agent' do
  subscribes :restart, 'template[/etc/neutron/neutron.conf]'
  action [:enable, :start]
end
