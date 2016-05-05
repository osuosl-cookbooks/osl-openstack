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
node.default['openstack']['compute']['network']['service_type'] = 'neutron'
node.default['openstack']['compute']['network']['plugins'] = %w(linuxbridge)
node.default['openstack']['identity']['saml']['idp_contact_type'] = 'support'
node.default['openstack']['identity']['verbose'] = 'false'
node.default['openstack']['libvirt']['virt_type'] = 'kvm'
node.default['openstack']['network']['service_plugins'] =
  ['neutron.services.l3_router.l3_router_plugin.L3RouterPlugin']
node.default['openstack']['network']['interface_driver'] =
  'neutron.agent.linux.interface.BridgeInterfaceDriver'
node.default['openstack']['network']['allow_overlapping_ips'] = 'True'
node.default['openstack']['network']['l3']['router_distributed'] = 'auto'
node.default['openstack']['network']['l3']['external_network_bridge'] = nil
node.default['openstack']['network']['dhcp']['enable_isolated_metadata'] =
  'True'
node.default['openstack']['network']['dhcp']['dhcp-option'] = '26,1450'
node.default['openstack']['network']['ml2']['type_drivers'] =
  "flat,vlan,vxlan\nextension_drivers = port_security"
node.default['openstack']['network']['ml2']['tenant_network_types'] =
  'vxlan'
node.default['openstack']['network']['ml2']['mechanism_drivers'] =
  'linuxbridge,l2population'
node.default['openstack']['network']['ml2']['flat_networks'] = '*'
node.default['openstack']['network']['ml2']['tunnel_id_ranges'] = '32769:34000'
node.default['openstack']['network']['ml2']['vni_ranges'] = '1:1000'
node.default['openstack']['network']['linuxbridge']['tenant_network_type'] = \
  'gre,vxlan'
node.default['openstack']['network']['linuxbridge']['enable_vxlan'] = true
node.default['openstack']['network']['linuxbridge']['l2_population'] = true
node.default['openstack']['network']['linuxbridge']['polling_interval'] =
  "2\nprevent_arp_spoofing = True"
node.default['openstack']['network']['linuxbridge']['firewall_driver'] =
  'neutron.agent.linux.iptables_firewall.IptablesFirewallDriver'
node.default['openstack']['dashboard']['keystone_default_role'] = '_member_'
node.default['openstack']['dashboard']['ssl']['cert'] = 'horizon.pem'
node.default['openstack']['dashboard']['ssl']['cert_url'] =
  'file:///etc/pki/tls/certs/wildcard.pem'
node.default['openstack']['dashboard']['ssl']['chain'] = 'wildcard-bundle.crt'
node.default['openstack']['dashboard']['ssl']['key'] = 'horizon.key'
node.default['openstack']['dashboard']['ssl']['key_url'] =
  'file:///etc/pki/tls/private/wildcard.key'
node.default['openstack']['endpoints']['compute-novnc']['scheme'] = 'https'
node.default['openstack']['release'] = 'liberty'
node.default['openstack']['secret']['key_path'] =
  '/etc/chef/encrypted_data_bag_secret'
node.default['openstack']['sysctl']['net.ipv4.conf.all.rp_filter'] = 0
node.default['openstack']['sysctl']['net.ipv4.conf.default.rp_filter'] = 0
node.default['openstack']['sysctl']['net.ipv4.ip_forward'] = 1
node.override['apache']['listen_addresses'] = %w(0.0.0.0)

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

# DB host lists on all address
node.default['openstack']['endpoints']['db']['host'] = '0.0.0.0'
# Set the endpoints for the database and mq servers
%w(
  compute
  bare-metal
  nova_api
  identity
  image
  network
  block-storage
  dashboard
  telemetry
  orchestration
  database).each do |c|
  node.default['openstack']['db'][c]['host'] = db_hostname
  node.default['openstack']['mq'][c]['rabbit']['host'] = endpoint_hostname
end

%w(
  identity
  identity-admin
  compute-api
  compute-ec2-api
  compute-ec2-admin
  compute-xvpvnc
  compute-novnc
  compute-vnc
  compute-metadata-api
  compute-serial-console
  network-api
  network-openvswitch
  image-api
  image-registry
  block-storage-api
  object-storage-api
  telemetry-api
  orchestration-api
  orchestration-api-cfn
  orchestration-api-cloudwatch
  database-api
  bare-metal-api
  dashboard-http
  dashboard-https
).each do |s|
  node.default['openstack']['endpoints']["#{s}-bind"]['host'] = '0.0.0.0'
  node.default['openstack']['endpoints'][s]['host'] = endpoint_hostname
end

node.default['openstack']['endpoints']['network-linuxbridge-bind']['host'] = '0.0.0.0'
node.default['openstack']['endpoints']['network-openvswitch-bind']['host'] = '0.0.0.0'
node.default['openstack']['endpoints']['network-linuxbridge']['host'] = \
  node['ipaddress']
node.default['openstack']['endpoints']['network-openvswitch']['host'] = \
  node['ipaddress']
node.default['openstack']['endpoints']['compute-vnc-proxy-bind']['host'] = \
  node['ipaddress']

# Set all URI's based on the endpoint hostname to by-pass attribute craziness
node.default['openstack']['endpoints']['identity-api']['host'] =
  endpoint_hostname
node.default['openstack']['endpoints']['identity-internal']['host'] =
  endpoint_hostname
node.default['openstack']['endpoints']['compute-serial-proxy']['host'] =
  endpoint_hostname
node.default['openstack']['endpoints']['mq']['host'] = '0.0.0.0'
node.default['openstack']['endpoints']['identity-api']['uri'] =
  "http://#{endpoint_hostname}:35357/v2.0"
node.default['openstack']['endpoints']['identity-admin']['uri'] =
  "http://#{endpoint_hostname}:5000/v2.0"
node.default['openstack']['endpoints']['compute-api']['uri'] =
  "http://#{endpoint_hostname}:8774/v2/%(tenant_id)s"
node.default['openstack']['endpoints']['compute-ec2-api']['uri'] =
  "http://#{endpoint_hostname}:8773/services/Cloud"
node.default['openstack']['endpoints']['compute-ec2-admin']['uri'] =
  "http://#{endpoint_hostname}:8773/services/Admin"
node.default['openstack']['endpoints']['compute-xvpvnc']['uri'] =
  "http://#{endpoint_hostname}:6081/console"
node.default['openstack']['endpoints']['compute-novnc']['uri'] =
  "https://#{endpoint_hostname}:6080/vnc_auto.html"
node.default['openstack']['endpoints']['image-api']['uri'] =
  "http://#{endpoint_hostname}:9292/v2"
node.default['openstack']['endpoints']['image-registry']['uri'] =
  "http://#{endpoint_hostname}:9191/v2"
node.default['openstack']['endpoints']['block-storage-api']['uri'] =
  "http://#{endpoint_hostname}:8776/v2/%(tenant_id)s"
node.default['openstack']['endpoints']['telemetry-api']['uri'] =
  "http://#{endpoint_hostname}:9000/v1"
node.default['openstack']['endpoints']['orchestration-api']['uri'] =
  "http://#{endpoint_hostname}:8004/v1/%(tenant_id)s"
node.default['openstack']['endpoints']['orchestration-api-cfn']['uri'] =
  "http://#{endpoint_hostname}:8000/v1"
node.default['openstack']['endpoints']['orchestration-api-cloudwatch']['uri'] =
  "http://#{endpoint_hostname}:8003/v1"

# node.default['openstack']['endpoints']['dashboard-http-bind']['host'] = '*'
# node.default['openstack']['endpoints']['dashboard-https-bind']['host'] = '*'

node.default['openstack']['yum']['repo-key'] = 'https://github.com/' \
 "redhat-openstack/rdo-release/raw/#{node['openstack']['release']}/" \
 'RPM-GPG-KEY-CentOS-SIG-Cloud'
node.default['openstack']['yum']['uri'] = 'http://centos.osuosl.org/$releasever/cloud/x86_64/openstack-liberty'

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
include_recipe 'openstack-common::openrc'
include_recipe 'openstack-common::client'
