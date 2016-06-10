#
# Cookbook Name:: osl-openstack
# Recipe:: default
#
# Copyright (C) 2014-2015 Oregon State University
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
node.default['authorization']['sudo']['include_sudoers_d'] = true
node.default['apache']['contact'] = 'hostmaster@osuosl.org'
node.default['openstack']['image']['notification_driver'] = 'messaging'
node.default['openstack']['block-storage']['notification_driver'] = 'messagingv2'
node.default['openstack']['mq']['image']['notifier_strategy'] = 'messagingv2'
node.default['openstack']['release'] = 'mitaka'
node.default['openstack']['secret']['key_path'] =
  '/etc/chef/encrypted_data_bag_secret'
# node.default['openstack']['sysctl']['net.ipv4.conf.all.rp_filter'] = 0
# node.default['openstack']['sysctl']['net.ipv4.conf.default.rp_filter'] = 0
# node.default['openstack']['sysctl']['net.ipv4.ip_forward'] = 1
node.default['openstack']['yum']['uri'] = \
  'http://centos.osuosl.org/$releasever/cloud/x86_64/openstack-' +
  node['openstack']['release']
node.default['openstack']['yum']['repo-key'] = 'https://github.com/' \
 "redhat-openstack/rdo-release/raw/#{node['openstack']['release']}/" \
 'RPM-GPG-KEY-CentOS-SIG-Cloud'
node.default['openstack']['compute']['conf'].tap do |conf|
  conf['DEFAULT']['linuxnet_interface_driver'] = \
    'nova.network.linux_net.NeutronLinuxBridgeInterfaceDriver'
  conf['DEFAULT']['dns_server'] = '140.211.166.130 140.211.166.131'
end
node.default['openstack']['network'].tap do |conf|
  conf['conf']['DEFAULT']['service_plugins'] =
    'neutron.services.l3_router.l3_router_plugin.L3RouterPlugin'
  conf['conf']['DEFAULT']['allow_overlapping_ips'] = 'True'
  conf['conf']['DEFAULT']['router_distributed'] = 'False'
  conf['dnsmasq']['upstream_dns_servers'] = %w(140.211.166.130 140.211.166.131)
end
node.default['openstack']['network_l3'].tap do |conf|
  conf['DEFAULT']['interface_driver'] =
    'neutron.agent.linux.interface.BridgeInterfaceDriver'
  conf['DEFAULT']['external_network_bridge'] = nil
end
node.default['openstack']['network_dhcp'].tap do |conf|
  conf['DEFAULT']['interface_driver'] =
    'neutron.agent.linux.interface.BridgeInterfaceDriver'
  conf['DEFAULT']['enable_isolated_metadata'] = 'True'
end
node.override['openstack']['network']['plugins']['ml2']['conf'].tap do |conf|
  conf['ml2']['type_drivers'] = 'flat,vlan,vxlan'
  conf['ml2']['extension_drivers'] = 'port_security'
  conf['ml2']['tenant_network_types'] = 'vxlan'
  conf['ml2']['mechanism_drivers'] = 'linuxbridge,l2population'
  conf['ml2_type_flat']['flat_networks'] = '*'
  conf['ml2_type_vlan']['network_vlan_ranges'] = nil
  conf['ml2_type_gre']['tunnel_id_ranges'] = '32769:34000'
  conf['ml2_type_vxlan']['vni_ranges'] = '1:1000'
end
node.default['openstack']['network']['plugins']['linuxbridge']['conf'].tap do |conf|
  conf['vlans']['tenant_network_type'] = 'gre,vxlan'
  conf['vxlan']['enable_vxlan'] = true
  conf['vxlan']['l2_population'] = true
  conf['agent']['polling_interval'] = 2
end
# conf['dhcp']['dhcp-option'] = '26,1450' needs fixed
node.default['openstack']['dashboard'].tap do |conf|
#  conf['ssl']['cert'] = 'horizon.pem'
  conf['ssl']['chain'] = 'wildcard-bundle.crt'
#  conf['ssl']['key'] = 'horizon.key'
end

# Dynamically find the hostname for the controller node, or use a pre-determined
# DNS name
if node['osl-openstack']['endpoint_hostname'].nil?
  if Chef::Config[:solo]
    Chef::Log.warn('This recipe uses search which Chef Solo does not support')
  else
    controller_node = search(:node, 'recipes:osl-openstack\:\:controller').first
    # Set the controller address to the public ipv4 on openstack, otherwise just
    # use the ipaddress.
    controller_address = unless controller_node.nil?
                           if controller_node['cloud']['public_ipv4'].nil?
                             controller_node['ipaddress']
                           else
                             controller_node['cloud']['public_ipv4']
                           end
                         end
    endpoint_hostname = if controller_node.nil?
                          node['ipaddress']
                        else
                          controller_address
                        end
  end
else
  endpoint_hostname = node['osl-openstack']['endpoint_hostname']
end

# Dynamically find the hostname for the db node, or use a pre-determined DNS
# name
if node['osl-openstack']['db_hostname'].nil?
  if Chef::Config[:solo]
    Chef::Log.warn('This recipe uses search which Chef Solo does not support')
  else
    db_node = search(:node, 'recipes:osl-openstack\:\:ops_database').first
    # Set the db address to the public ipv4 on openstack, otherwise just use the
    # ipaddress.
    db_address = unless db_node.nil?
                   if db_node['cloud']['public_ipv4'].nil?
                     db_node['ipaddress']
                   else
                     db_node['cloud']['public_ipv4']
                   end
                 end
    db_hostname = if db_node.nil?
                    node['ipaddress']
                  else
                    db_address
                  end
  end
else
  db_hostname = node['osl-openstack']['db_hostname']
end

# Set memcache server to controller node
memcached_servers = "#{endpoint_hostname}:11211"
node.default['openstack']['memcached_servers'] = [memcached_servers]

# Endpoints
node.default['openstack']['endpoints'].tap do |conf|
  conf['db']['host'] = db_hostname
  conf['mq']['host'] = endpoint_hostname
end
# Binding
node.default['openstack']['bind_service'].tap do |conf|
  conf['mq']['host'] = '0.0.0.0'
  conf['db']['host'] = '0.0.0.0'
  conf['admin']['identity']['host'] = '0.0.0.0'
  conf['main']['identity']['host'] = '0.0.0.0'
end

# Looping magic for endpoints and binding
%w(
  identity
  compute-xvpvnc
  compute-novnc
  compute-metadata-api
  compute-vnc
  compute-api
  compute-serial-proxy
  network
).each do |service|
  node.default['openstack']['bind_service']['all'][service]['host'] = '0.0.0.0'
  node.default['openstack']['endpoints'].tap do |conf|
    conf['admin'][service]['host'] = endpoint_hostname
    conf['public'][service]['host'] = endpoint_hostname
    conf['internal'][service]['host'] = endpoint_hostname
  end
end

# Set database attributes with our suffix setting
database_suffix = node['osl-openstack']['database_suffix']
if database_suffix
  node['osl-openstack']['databases'].each_pair do |db, name|
    node.default['openstack']['db'][db]['db_name'] =
      "#{name}_#{database_suffix}"
    node.default['openstack']['db'][db]['username'] =
      "#{name}_#{database_suffix}"
  end
end

# set data bag attributes with our prefix
databag_prefix = node['osl-openstack']['databag_prefix']
if databag_prefix
  node['osl-openstack']['data_bags'].each do |d|
    node.default['openstack']['secret']["#{d}_data_bag"] =
      "#{databag_prefix}_#{d}"
  end
end

yum_repository 'OSL-Openpower' do
  description "OSL Openpower repo for #{node['platform_family']}-" +
              node['platform_version']
  gpgkey node['osl-openstack']['openpower']['yum']['repo-key']
  gpgcheck false
  baseurl node['osl-openstack']['openpower']['yum']['uri']
  enabled true
  only_if { %w(ppc64 ppc64le).include?(node['kernel']['machine']) }
  action :add
end

include_recipe 'base::ifconfig'
include_recipe 'selinux::permissive'
include_recipe 'openstack-common'
include_recipe 'openstack-common::logging'
include_recipe 'openstack-common::sysctl'
include_recipe 'openstack-identity::openrc'
include_recipe 'openstack-common::client'
include_recipe 'openstack-telemetry::client'
