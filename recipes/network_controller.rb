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

osl_repos_openstack 'network'
osl_openstack_client 'network'
osl_firewall_openstack 'network'

s = os_secrets
n = s['network']

osl_openstack_user n['service']['user'] do
  domain_name 'default'
  role_name 'admin'
  project_name 'service'
  password n['service']['pass']
  action [:create, :grant_role]
end

osl_openstack_service 'neutron' do
  type 'network'
end

%w(
  admin
  internal
  public
).each do |int|
  osl_openstack_endpoint "network-#{int}" do
    endpoint_name 'network'
    service_name 'neutron'
    interface int
    url "http://#{n['endpoint']}:9696"
    region n['region']
  end
end

package %w(
  conntrack-tools
  ebtables
  openstack-neutron
  openstack-neutron-linuxbridge
  openstack-neutron-metering-agent
  openstack-neutron-ml2
)

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
  subscribes :run, 'template[/etc/neutron/neutron.conf]', :immediately
end

template '/etc/neutron/metadata_agent.ini' do
  owner 'root'
  group 'neutron'
  mode '0640'
  sensitive true
  variables(
    memcached_endpoint: s['memcached']['endpoint'],
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
  ip_cmd = "ip netns exec qdhcp-#{network['uuid']}"

  bash "block external dns on #{network['name']}" do
    code <<~EOL
      #{ip_cmd} iptables -A INPUT -p tcp --dport 53 ! -s #{network['subnet']} -j DROP
      #{ip_cmd} iptables -A INPUT -p udp --dport 53 ! -s #{network['subnet']} -j DROP
    EOL
    not_if "#{ip_cmd} iptables -S | egrep \"#{network['subnet']}.*port 53.*DROP\""
  end
end
