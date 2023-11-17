#
# Cookbook:: osl-openstack
# Recipe:: dashboard
#
# Copyright:: 2016-2023, Oregon State University
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

node.default['osl-apache']['listen'] = %w(80 443)

include_recipe 'certificate::wildcard'
include_recipe 'osl-memcached'
include_recipe 'osl-apache'
include_recipe 'osl-apache::mod_wsgi'
include_recipe 'osl-apache::mod_ssl'

package 'openstack-dashboard'

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
    secret_key: d['secret_key'],
    auth_url: auth_endpoint,
    memcache_servers: s['memcached']['endpoint']
  )
  notifies :run, 'execute[horizon: compress]'
  notifies :reload, 'apache2_service[osuosl]'
end

apache_app 'horizon' do
  cookbook 'osl-openstack'
  server_name d['endpoint']
  server_aliases d['aliases'] if d['aliases']
  template 'wsgi-horizon.conf.erb'
  notifies :run, 'execute[horizon: compress]'
  notifies :reload, 'apache2_service[osuosl]'
end

execute 'horizon: compress' do
  command <<~EOC
    /usr/bin/python2 /usr/share/openstack-dashboard/manage.py collectstatic --noinput --clear -v0
    /usr/bin/python2 /usr/share/openstack-dashboard/manage.py compress --force -v0
  EOC
  action :nothing
end
