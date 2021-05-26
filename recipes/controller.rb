#
# Cookbook:: osl-openstack
# Recipe:: controller
#
# Copyright:: 2014-2021, Oregon State University
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
node.default['osl-openstack']['node_type'] = 'controller'
node.default['osl-apache']['install_resource'] = false
node.default['osl-apache']['listen'] = %w(80 443)

include_recipe 'osl-openstack::default'

osl_firewall_openstack 'osl-openstack'
osl_firewall_vnc 'osl-openstack'

cluster_hosts = %w(127.0.0.1)
search(:node, "role:#{node['osl-openstack']['cluster_role']}") do |n|
  cluster_hosts << n['ipaddress']
end

osl_firewall_memcached 'osl-openstack' do
  allowed_ipv4 cluster_hosts.flatten.sort
end

include_recipe 'memcached'
include_recipe 'osl-openstack::identity'
include_recipe 'osl-apache::default'
include_recipe 'osl-openstack::image'
include_recipe 'osl-openstack::network' unless node['osl-openstack']['separate_network_node']
include_recipe 'osl-openstack::compute_controller'
include_recipe 'osl-openstack::block_storage_controller'
include_recipe 'osl-openstack::orchestration'
include_recipe 'osl-openstack::telemetry'
include_recipe 'osl-openstack::dashboard'
include_recipe 'osl-openstack::mon'

# Ensure apache is installed the OSUOSL Way™
edit_resource(:apache2_install, 'openstack') do
  modules osl_apache_default_modules
  mpm node['osl-apache']['mpm']
  mpm_conf(
    maxrequestworkers: node['osl-apache']['maxrequestworkers'] || osl_apache_max_clients,
    serverlimit: node['osl-apache']['serverlimit'] || osl_apache_max_clients
  )
  mod_conf(
    status: {
      extended_status: 'On',
    }
  )
end
