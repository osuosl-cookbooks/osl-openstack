#
# Cookbook:: osl-openstack
# Recipe:: container_controller
#
# Copyright:: 2019, Oregon State University
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
etcd_hosts = %w(127.0.0.1 140.211.167.136)
search(:node, "role:#{node['osl-openstack']['cluster_role']}") do |n|
  etcd_hosts << n['ipaddress']
end

node.default['firewall']['etcd']['range']['4'] = etcd_hosts.sort.uniq

include_recipe 'osl-openstack'
include_recipe 'firewall::openstack'
include_recipe 'firewall::etcd'

ssl_dir = node['osl-openstack']['zun_ssl_dir']
zun = node['osl-openstack']['zun']

directory ssl_dir

certificate_manage 'zun' do
  cert_path ssl_dir
  cert_file zun['cert_file']
  key_file  zun['key_file']
  chain_file 'zun-bundle.crt'
  nginx_cert true
  owner node['openstack']['container']['user']
  group node['openstack']['container']['group']
  notifies :restart, 'service[zun-wsproxy]'
end

include_recipe 'openstack-container::wsproxy'
include_recipe 'openstack-container::api'
include_recipe 'openstack-container::dashboard'
include_recipe 'openstack-container::identity_registration'

endpoint_hostname = node['osl-openstack']['endpoint_hostname']

edit_resource(:etcd_service, 'openstack') do
  advertise_client_urls "http://#{endpoint_hostname}:2379"
  initial_advertise_peer_urls "http://#{endpoint_hostname}:2380"
  initial_cluster "openstack=http://#{endpoint_hostname}:2380"
  listen_client_urls 'http://0.0.0.0:2379'
  listen_peer_urls 'http://0.0.0.0:2380'
end
