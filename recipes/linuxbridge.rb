#
# Cookbook:: osl-openstack
# Recipe:: linuxbridge
#
# Copyright:: 2015-2021, Oregon State University
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
include_recipe 'osl-openstack'
include_recipe 'openstack-network'

node_type = node['osl-openstack']['node_type']
int_mappings = []
node['osl-openstack']['physical_interface_mappings'].each do |int|
  interface = int[node_type][node['fqdn']] || int[node_type]['default']
  int_mappings.push("#{int['name']}:#{interface}")
end

# Get the IP for the interface we're using VXLAN for
vxlan = node['osl-openstack']['vxlan_interface']
vxlan_interface = vxlan[node_type][node['fqdn']] || vxlan[node_type]['default']
vxlan_addrs = node['network']['interfaces'][vxlan_interface]
vxlan_ip = if vxlan_addrs.nil? || vxlan_addrs['addresses'].empty?
             # Fall back to localhost if the interface has no IP
             '127.0.0.1'
           else
             address = vxlan_addrs['addresses'].find do |_, attrs|
               attrs['family'] == 'inet'
             end
             if address.nil?
               '127.0.0.1'
             else
               address[0]
             end
           end

node.default['openstack']['network']['plugins']['linuxbridge']['conf']
    .tap do |conf|
  conf['linux_bridge']['physical_interface_mappings'] = int_mappings.join(',')
  conf['vxlan']['local_ip'] = vxlan_ip
end

include_recipe 'openstack-network::ml2_linuxbridge'

systemd_service_drop_in node['openstack']['network']['platform']['neutron_linuxbridge_agent_service'] do
  unit_part_of "#{node['iptables-ng']['service_ipv4']}.service"
  override "#{node['openstack']['network']['platform']['neutron_linuxbridge_agent_service']}.service"
end
