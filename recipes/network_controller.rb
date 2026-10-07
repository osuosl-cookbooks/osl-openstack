#
# Cookbook:: osl-openstack
# Recipe:: network_controller
#
# Copyright:: 2015-2026, Oregon State University
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

osl_openstack_client 'network' do
  firewall true
end

s = os_secrets
n = s['network']

osl_openstack_service_user n['service']['user'] do
  password n['service']['pass']
end

osl_openstack_api 'neutron' do
  type 'network'
  endpoint_name 'network'
  url "http://#{n['endpoint']}:9696"
  region n['region']
end

package %w(
  conntrack-tools
  ebtables
)

package 'osuosl-openstack-neutron-controller' do
  action :upgrade
end

include_recipe 'osl-openstack::network_common'

execute 'neutron: db_sync' do
  command <<~EOC
    neutron-db-manage \
    --config-file /etc/neutron/neutron.conf \
    --config-file /etc/neutron/plugins/ml2/ml2_conf.ini \
    upgrade head
  EOC
  user 'neutron'
  group 'neutron'
  action :nothing
  only_if { openstack_db_node? }
  # db-manage reads both, and ml2_conf.ini lands after neutron.conf on a new node
  only_if { ::File.exist?('/etc/neutron/plugins/ml2/ml2_conf.ini') }
  subscribes :run, 'template[/etc/neutron/neutron.conf]', :immediately
  subscribes :run, 'cookbook_file[/etc/neutron/plugins/ml2/ml2_conf.ini]', :immediately
end

openstack_db_sync_on_upgrade('neutron', 'osuosl-openstack-neutron-controller', ['neutron: db_sync'])

template '/etc/neutron/metadata_agent.ini' do
  owner 'root'
  group 'neutron'
  mode '0640'
  sensitive true
  variables(
    memcached_endpoint: openstack_memcached_servers,
    metadata_proxy_shared_secret: n['metadata_proxy_shared_secret'],
    nova_metadata_host: n['nova_metadata_host']
  )
  notifies :restart, 'service[neutron-metadata-agent]'
end

cookbook_file '/etc/neutron/dhcp_agent.ini' do
  owner 'root'
  group 'neutron'
  notifies :restart, 'service[neutron-dhcp-agent]'
end

cookbook_file '/etc/neutron/l3_agent.ini' do
  owner 'root'
  group 'neutron'
  notifies :restart, 'service[neutron-l3-agent]'
end

cookbook_file '/etc/neutron/metering_agent.ini' do
  owner 'root'
  group 'neutron'
  notifies :restart, 'service[neutron-metering-agent]'
end

%w(
  neutron-dhcp-agent
  neutron-l3-agent
  neutron-metadata-agent
  neutron-metering-agent
  neutron-server
).each do |srv|
  service srv do
    subscribes :restart, 'template[/etc/neutron/neutron.conf]'
    subscribes :restart, 'cookbook_file[/etc/neutron/plugins/ml2/ml2_conf.ini]'
    action [:enable, :start]
  end
end

n['physical_interface_mappings'].each do |network|
  next if network['subnet'].nil? || network['uuid'].nil?
  netns = "qdhcp-#{network['uuid']}"
  ip_cmd = "ip netns exec #{netns}"

  bash "block external dns on #{network['name']}" do
    code <<~EOL
      #{ip_cmd} iptables -A INPUT -p tcp --dport 53 ! -s #{network['subnet']} -j DROP
      #{ip_cmd} iptables -A INPUT -p udp --dport 53 ! -s #{network['subnet']} -j DROP
    EOL
    # In HA mode the DHCP scheduler may not have placed this network on
    # this controller's neutron-dhcp-agent yet, so the qdhcp namespace
    # won't exist locally. Skip rather than fail; the next chef run
    # after the scheduler assigns the network will apply the rule.
    only_if { ::File.exist?("/run/netns/#{netns}") }
    not_if "#{ip_cmd} iptables -S | egrep \"#{network['subnet']}.*port 53.*DROP\""
  end
end
