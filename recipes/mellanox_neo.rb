#
# Cookbook:: osl-openstack
# Recipe:: mellanox_neo
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
include_recipe 'osl-apache'
include_recipe 'apache2::mod_ssl'
include_recipe 'apache2::mod_proxy'
include_recipe 'apache2::mod_proxy_http'
include_recipe 'apache2::mod_proxy_balancer'
include_recipe 'yum-epel'
include_recipe 'certificate::wildcard'

delete_resource(:directory, "#{node['apache']['dir']}/conf.d")

package 'yum-plugin-priorities'

neo = node['osl-openstack']['mellanox_neo']

yum_repository 'mellanox-neo' do
  description 'Mellanox Neo'
  url "http://packages.osuosl.org/repositories/#{node['platform']}-$releasever/mellanox-neo"
  gpgcheck false
  priority '1'
end

neo['packages'].each do |p|
  package p
end

neo['services'].each do |s|
  service s do
    action [:enable, :start]
  end
end

apache_app neo['server_hostname'] do
  directory '/opt/neo/controller/docs'
  directive_http [
    'RewriteCond %{HTTPS} !=on',
    'RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R,L]'
  ]
  ssl_enable true
  cert_chain '/etc/pki/tls/certs/wildcard-bundle.crt'
  cert_file '/etc/pki/tls/certs/wildcard.pem'
  cert_key '/etc/pki/tls/private/wildcard.key'
  include_config true
  include_name 'neo'
end
