#
# Cookbook:: osl-openstack
# Recipe:: dashboard
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

osl_repos_openstack 'dashboard'
osl_openstack_client 'dashboard'
osl_firewall_openstack 'dashboard'
osl_openstack_openrc 'dashboard'

listen_ip = openstack_api_listen_ip
node.default['osl-apache']['listen'] = %w(80 443).map { |p| "#{listen_ip}:#{p}" }

include_recipe 'osl-apache'
include_recipe 'osl-apache::mod_wsgi'
include_recipe 'osl-apache::mod_ssl'

# Nagios apache monitoring. check_http runs locally over NRPE (configured by
# osl-apache::mon via the apache role, invoked server-side by the apache_httpd
# check), so point it at whatever address apache actually listens on: the
# per-host backend IP in HA, or node['ipaddress'] on a single-controller
# deploy (openstack_local_api_endpoint already returns the latter off-HA, so
# this is a no-op there). Declare the check here with the override already set
# - before osl-apache::mon's own include - because the nrpe check captures its
# -I at compile time on first include.
node.override['osl-nrpe']['check_http']['ipaddress'] = openstack_local_api_endpoint

# In HA apache binds an IPv4-only backend IP and serves no IPv6 of its own -
# IPv6 clients terminate on the haproxy VIP - so drop this controller from the
# per-host apache_http6 check. The VIP is monitored separately via its own
# (unmanaged) Nagios host. Off-HA apache still binds wildcard and serves the
# public IPv6, so the check stays.
node.override['nagios']['_http_address6'] = nil if openstack_tls_on_haproxy?

include_recipe 'osl-nrpe::check_http'

package 'openstack-dashboard'

certificate_manage 'wildcard-dashboard' do
  search_id 'wildcard'
  cert_file 'wildcard.pem'
  key_file 'wildcard.key'
  chain_file 'wildcard-bundle.crt'
  notifies :reload, 'apache2_service[osuosl]'
end

file '/etc/httpd/conf.d/openstack-dashboard.conf' do
  action :delete
  notifies :reload, 'apache2_service[osuosl]'
  notifies :delete, 'directory[purge distro conf.d]', :immediately
end

file '/usr/lib/systemd/system/httpd.service.d/openstack-dashboard.conf' do
  action :delete
  notifies :run, 'execute[systemctl daemon-reload]', :immediately
end

execute 'systemctl daemon-reload' do
  action :nothing
end

directory 'purge distro conf.d' do
  path '/etc/httpd/conf.d'
  recursive true
  action :nothing
end

s = os_secrets
d = s['dashboard']
auth_endpoint = s['identity']['endpoint']

template '/etc/openstack-dashboard/local_settings' do
  group 'apache'
  mode '0640'
  sensitive true
  variables(
    auth_url: auth_endpoint,
    memcache_servers: openstack_memcached_endpoints,
    regions: d['regions'],
    secret_key: d['secret_key'],
    # Django needs to trust haproxy's X-Forwarded-Proto when haproxy
    # terminates TLS - otherwise it builds http:// redirect URLs and
    # drops the secure-cookie flag.
    haproxy_tls: openstack_tls_on_haproxy?
  )
  notifies :run, 'execute[horizon: compress]'
  notifies :reload, 'apache2_service[osuosl]'
end

apache_app 'horizon' do
  cookbook 'osl-openstack'
  server_name d['endpoint']
  server_aliases d['aliases'] if d['aliases']
  server_address listen_ip
  template 'wsgi-horizon.conf.erb'
  # In HA mode haproxy on the VIP terminates TLS and forwards plain
  # HTTP to this vhost; the wsgi-horizon.conf.erb template drops its
  # SSLEngine block when this flag is set.
  template_params(haproxy_tls: openstack_tls_on_haproxy?)
  notifies :run, 'execute[horizon: compress]'
  notifies :reload, 'apache2_service[osuosl]'
end

execute 'horizon: compress' do
  command <<~EOC
    #{openstack_python_bin} /usr/share/openstack-dashboard/manage.py collectstatic --noinput --clear -v0
    #{openstack_python_bin} /usr/share/openstack-dashboard/manage.py compress --force -v0
  EOC
  action :nothing
end
