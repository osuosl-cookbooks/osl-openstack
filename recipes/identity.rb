#
# Cookbook:: osl-openstack
# Recipe:: identity
#
# Copyright:: 2016-2026, Oregon State University
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
osl_repos_openstack 'identity'
osl_openstack_client 'identity'
osl_firewall_openstack 'identity'
osl_openstack_openrc 'identity'

listen_ip = openstack_api_listen_ip
node.default['osl-apache']['listen'] = %w(80 443).map { |p| "#{listen_ip}:#{p}" }

include_recipe 'osl-memcached'
include_recipe 'osl-apache'
include_recipe 'osl-apache::mod_wsgi'
include_recipe 'osl-apache::mod_ssl'

package 'openstack-keystone'

s = os_secrets

certificate_manage 'wildcard-identity' do
  search_id 'wildcard'
  cert_file 'wildcard.pem'
  key_file 'wildcard.key'
  chain_file 'wildcard-bundle.crt'
  notifies :reload, 'apache2_service[osuosl]'
end

endpoint = s['identity']['endpoint']
admin_pass = s['users']['admin']
fernet_keys = safe_dig(s, 'identity', 'fernet_keys')

if fernet_keys
  # On a fresh node the openstack-keystone package creates /etc/keystone
  # but not /etc/keystone/fernet-keys; that dir is normally created by
  # `keystone-manage fernet_setup` (below), which runs after these file
  # resources. Pre-create it so the data-bag keys can be written on the
  # very first chef run.
  directory '/etc/keystone/fernet-keys' do
    owner 'keystone'
    group 'keystone'
    mode '0700'
  end

  fernet_keys.each do |key, val|
    file "/etc/keystone/fernet-keys/#{key}" do
      content val
      owner 'keystone'
      group 'keystone'
      mode '600'
      sensitive true
      notifies :reload, 'apache2_service[osuosl]'
    end
  end
end

template '/etc/keystone/keystone.conf' do
  owner 'root'
  group 'keystone'
  mode '0640'
  sensitive true
  variables(
    endpoint: endpoint,
    transport_url: openstack_transport_url,
    memcached_endpoint: openstack_memcached_servers,
    database_connection: openstack_database_connection('identity')
  )
  notifies :run, 'execute[keystone: db_sync]', :immediately
  notifies :reload, 'apache2_service[osuosl]'
end

execute 'keystone: db_sync' do
  command 'keystone-manage db_sync'
  user 'keystone'
  group 'keystone'
  action :nothing
end

execute 'keystone: fernet_setup' do
  command 'keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone'
  creates '/etc/keystone/fernet-keys/0'
end

execute 'keystone: credential_setup' do
  command 'keystone-manage credential_setup --keystone-user keystone --keystone-group keystone'
  creates '/etc/keystone/credential-keys/0'
end

execute 'keystone: bootstrap' do
  command <<~EOC
    keystone-manage bootstrap \
      --bootstrap-password #{admin_pass} \
      --bootstrap-username admin \
      --bootstrap-project-name admin \
      --bootstrap-role-name admin \
      --bootstrap-service-name keystone \
      --bootstrap-admin-url https://#{endpoint}:5000/v3/ \
      --bootstrap-internal-url https://#{endpoint}:5000/v3/ \
      --bootstrap-public-url https://#{endpoint}:5000/v3/ \
      --bootstrap-region-id RegionOne && \
    touch /etc/keystone/bootstrapped
  EOC
  sensitive true
  creates '/etc/keystone/bootstrapped'
end

apache_app 'keystone' do
  server_name endpoint
  server_aliases s['identity']['aliases'] if s['identity']['aliases']
  server_address listen_ip
  cookbook 'osl-openstack'
  template 'wsgi-keystone.conf.erb'
  notifies :reload, 'apache2_service[osuosl]', :immediately
end

osl_openstack_role 'service'

osl_openstack_project 'service' do
  domain_name 'default'
end
