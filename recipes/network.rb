#
# Cookbook:: osl-openstack
# Recipe:: network
#
# Copyright:: 2016-2023, Oregon State University
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

osl_firewall_openstack 'osl-openstack'

include_recipe 'openstack-network::identity_registration'
include_recipe 'openstack-network::ml2_core_plugin'
include_recipe 'openstack-network'
include_recipe 'osl-openstack::linuxbridge'
include_recipe 'openstack-network::plugin_config'
include_recipe 'openstack-network::server'
include_recipe 'openstack-network::l3_agent'
include_recipe 'openstack-network::dhcp_agent'
include_recipe 'openstack-network::metadata_agent'
include_recipe 'openstack-network::metering_agent'

# Block external DNS requests to networks we have selected. This is to prevent them to be seen as open resolvers and
# used in amplification attacks.
node['osl-openstack']['physical_interface_mappings'].each do |network|
  next if network['subnet'].nil? || network['uuid'].nil?
  ip_cmd = "ip netns exec qdhcp-#{network['uuid']}"
  bash "block external dns on #{network['name']}" do
    code <<-EOL
#{ip_cmd} iptables -A INPUT -p tcp --dport 53 ! -s #{network['subnet']} -j DROP
#{ip_cmd} iptables -A INPUT -p udp --dport 53 ! -s #{network['subnet']} -j DROP
    EOL
    not_if "#{ip_cmd} iptables -S | egrep \"#{network['subnet']}.*port 53.*DROP\""
  end
end
