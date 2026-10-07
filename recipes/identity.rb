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
osl_openstack_client 'identity' do
  firewall true
  openrc true
end

listen_ip = openstack_api_listen_ip
node.default['osl-apache']['listen'] = %w(80 443).map { |p| "#{listen_ip}:#{p}" }
# The default vhost is named for the fqdn, which can be Horizon's endpoint; sort it
# last so Horizon's :80 redirect wins, as it did before osl-apache cf9c4bb.
node.default['osl-apache']['default_site_first'] = false

# Declare memcached ourselves so we can open the firewall to all
# OSL-managed nodes (peer controllers for horizon sessions, compute
# nodes for keystone_authtoken caching). Default localhost-only would
# shard horizon sessions per-controller and force a re-login on every
# VIP failover, and leaves nova-compute silently falling back to
# direct keystone validation. Mirrors AMQP's `osl_only: true`.
node.default['osl-memcached']['default_service'] = false
include_recipe 'osl-memcached'

osl_memcached 'memcached' do
  port 11211
  osl_only true
end

include_recipe 'osl-apache'
include_recipe 'osl-apache::mod_proxy_uwsgi'
include_recipe 'osl-apache::mod_ssl'
# Apache sits behind haproxy in HA mode; mod_remoteip rewrites
# REMOTE_ADDR from haproxy's X-Forwarded-For. ha.rb populates the
# trusted_proxy attribute; here we just load the module (after
# osl-apache has captured the per-host `listen` value).
include_recipe 'osl-apache::mod_remoteip' if openstack_tls_on_haproxy?

package 'osuosl-openstack-keystone' do
  action :upgrade
end

s = os_secrets

certificate_manage 'wildcard-identity' do
  search_id 'wildcard'
  cert_file 'wildcard.pem'
  key_file 'wildcard.key'
  chain_file 'wildcard-bundle.crt'
  notifies :reload, 'apache2_service[osuosl]'
end

endpoint = openstack_auth_endpoint
admin_pass = s['users']['admin']
fernet_keys = safe_dig(s, 'identity', 'fernet_keys')

if fernet_keys
  # fernet_setup below creates this dir, but the data bag keys are written
  # first on a new node
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
      notifies :restart, 'service[keystone-uwsgi]'
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
    heartbeat_in_pthread: true,
    **openstack_messaging_template_vars,
    memcached_endpoint: openstack_memcached_servers,
    database_connection: openstack_database_connection('identity')
  )
  notifies :run, 'execute[keystone: db_sync]', :immediately
  notifies :restart, 'service[keystone-uwsgi]'
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

directory openstack_uwsgi_cache_dir('keystone') do
  owner 'keystone'
  group 'keystone'
  mode '0750'
end

template '/etc/keystone/keystone-uwsgi.ini' do
  source 'uwsgi.ini.erb'
  group 'keystone'
  mode '0640'
  variables(
    chdir: openstack_venv('keystone'),
    wsgi_file: "#{openstack_venv('keystone')}/bin/keystone-wsgi-public",
    socket: '/run/keystone/uwsgi.sock',
    user: 'keystone',
    processes: 5,
    threads: 1,
    env: openstack_uwsgi_env('keystone')
  )
  notifies :restart, 'service[keystone-uwsgi]'
end

# uWSGI unit shipped by osuosl-openstack-keystone
service 'keystone-uwsgi' do
  action [:enable, :start]
end

apache_app 'keystone' do
  server_name endpoint
  server_aliases s['identity']['aliases'] if s['identity']['aliases']
  server_address listen_ip
  cookbook 'osl-openstack'
  template 'wsgi-keystone.conf.erb'
  # haproxy terminates TLS at the VIP in HA, so the vhost drops its SSL block
  template_params(haproxy_tls: openstack_tls_on_haproxy?)
  notifies :reload, 'apache2_service[osuosl]', :immediately
end

osl_openstack_role 'service'

osl_openstack_project 'service' do
  domain_name 'default'
end
