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

osl_openstack_client 'dashboard' do
  firewall true
  openrc true
end

listen_ip = openstack_api_listen_ip
node.default['osl-apache']['listen'] = %w(80 443).map { |p| "#{listen_ip}:#{p}" }
# The default vhost is named for the fqdn, which can be Horizon's endpoint; sort it
# last so Horizon's :80 redirect wins, as it did before osl-apache cf9c4bb.
node.default['osl-apache']['default_site_first'] = false

include_recipe 'osl-apache'
include_recipe 'osl-apache::mod_proxy_uwsgi'
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

package 'osuosl-openstack-horizon'

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
auth_endpoint = openstack_auth_endpoint
static_root = '/var/www/horizon/static'

# /var/lib/horizon is 0750 horizon, so Apache could not serve the assets from there
directory static_root do
  owner 'horizon'
  group 'apache'
  mode '0755'
  recursive true
end

template '/etc/horizon/local_settings.py' do
  source 'local_settings.erb'
  group 'horizon'
  mode '0640'
  sensitive true
  variables(
    auth_url: auth_endpoint,
    memcache_servers: openstack_memcached_endpoints,
    regions: d['regions'],
    secret_key: d['secret_key'],
    static_root: static_root,
    # Trust haproxy's X-Forwarded-Proto so Django builds https URLs and secure cookies
    haproxy_tls: openstack_tls_on_haproxy?
  )
  notifies :run, 'execute[horizon: compress]'
  notifies :restart, 'service[horizon-uwsgi]'
end

# Django imports openstack_dashboard.local.local_settings from the venv
link "#{openstack_python_sitelib('horizon')}/openstack_dashboard/local/local_settings.py" do
  to '/etc/horizon/local_settings.py'
end

template '/etc/horizon/horizon-uwsgi.ini' do
  source 'uwsgi.ini.erb'
  group 'horizon'
  mode '0640'
  variables(
    chdir: openstack_python_sitelib('horizon'),
    wsgi_file: "#{openstack_python_sitelib('horizon')}/openstack_dashboard/wsgi.py",
    pythonpath: openstack_python_sitelib('horizon'),
    socket: '/run/horizon/uwsgi.sock',
    user: 'horizon',
    processes: 4,
    threads: 1
  )
  notifies :restart, 'service[horizon-uwsgi]'
end

# uWSGI unit shipped by osuosl-openstack-horizon
service 'horizon-uwsgi' do
  action [:enable, :start]
end

apache_app 'horizon' do
  cookbook 'osl-openstack'
  server_name d['endpoint']
  server_aliases d['aliases'] if d['aliases']
  server_address listen_ip
  template 'wsgi-horizon.conf.erb'
  # haproxy terminates TLS at the VIP in HA, so the vhost drops its SSL block
  template_params(haproxy_tls: openstack_tls_on_haproxy?, static_root: static_root)
  notifies :run, 'execute[horizon: compress]'
  notifies :reload, 'apache2_service[osuosl]'
end

execute 'horizon: compress' do
  command <<~EOC
    #{openstack_venv('horizon')}/bin/django-admin collectstatic --settings=openstack_dashboard.settings --noinput --clear -v0
    #{openstack_venv('horizon')}/bin/django-admin compress --settings=openstack_dashboard.settings --force -v0
  EOC
  user 'horizon'
  group 'horizon'
  action :nothing
end
