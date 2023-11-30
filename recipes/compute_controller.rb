#
# Cookbook:: osl-openstack
# Recipe:: compute_controller
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

osl_repos_openstack 'compute'
osl_openstack_client 'compute'
osl_firewall_openstack 'compute'

s = os_secrets
c = s['compute']
p = s['placement']
auth_endpoint = s['identity']['endpoint']

include_recipe 'osl-apache'
include_recipe 'osl-apache::mod_wsgi'

osl_openstack_user p['service']['user'] do
  domain_name 'default'
  role_name 'admin'
  project_name 'service'
  password p['service']['pass']
  action [:create, :grant_role]
end

osl_openstack_user c['service']['user'] do
  domain_name 'default'
  role_name 'admin'
  project_name 'service'
  password c['service']['pass']
  action [:create, :grant_role]
end

osl_openstack_service 'placement' do
  type 'placement'
end

osl_openstack_service 'nova' do
  type 'compute'
end

%w(
  admin
  internal
  public
).each do |int|
  osl_openstack_endpoint "placement-#{int}" do
    endpoint_name 'placement'
    service_name 'placement'
    interface int
    url "http://#{p['endpoint']}:8778"
    region 'RegionOne'
  end

  osl_openstack_endpoint "compute-#{int}" do
    endpoint_name 'compute'
    service_name 'nova'
    interface int
    url "http://#{p['endpoint']}:8774/v2.1"
    region 'RegionOne'
  end
end

package %w(
  openstack-nova-api
  openstack-nova-conductor
  openstack-nova-console
  openstack-nova-novncproxy
  openstack-nova-scheduler
  openstack-placement-api
  python2-osc-placement
)

file '/etc/httpd/conf.d/00-placement-api.conf' do
  action :delete
  notifies :reload, 'apache2_service[compute]'
  notifies :delete, 'directory[purge distro conf.d]', :immediately
end

directory 'purge distro conf.d' do
  path '/etc/httpd/conf.d'
  recursive true
  action :nothing
end

template '/etc/placement/placement.conf' do
  owner 'root'
  group 'placement'
  mode '0640'
  sensitive true
  variables(
    auth_endpoint: auth_endpoint,
    database_connection: openstack_database_connection('placement'),
    memcached_endpoint: s['memcached']['endpoint'],
    service_pass: p['service']['pass']
  )
  notifies :run, 'execute[placement: db_sync]', :immediately
  notifies :reload, 'apache2_service[compute]'
end

include_recipe 'osl-openstack::compute_common'

execute 'placement: db_sync' do
  command 'placement-manage db sync'
  user 'placement'
  group 'placement'
  action :nothing
end

execute 'nova: api_db_sync' do
  command 'nova-manage api_db sync'
  user 'nova'
  group 'nova'
  action :nothing
  subscribes :run, 'template[/etc/nova/nova.conf]', :immediately
end

execute 'nova: register cell0' do
  command 'nova-manage cell_v2 map_cell0'
  user 'nova'
  group 'nova'
  not_if 'nova-manage cell_v2 list_cells | grep -q cell0'
  action :nothing
  subscribes :run, 'template[/etc/nova/nova.conf]', :immediately
end

execute 'nova: create cell1' do
  command 'nova-manage cell_v2 create_cell --name=cell1'
  user 'nova'
  group 'nova'
  not_if 'nova-manage cell_v2 list_cells | grep -q cell1'
  action :nothing
  subscribes :run, 'template[/etc/nova/nova.conf]', :immediately
end

execute 'nova: db_sync' do
  command 'nova-manage db sync'
  user 'nova'
  group 'nova'
  action :nothing
  subscribes :run, 'template[/etc/nova/nova.conf]', :immediately
end

execute 'nova: discover hosts' do
  command 'nova-manage cell_v2 discover_hosts'
  user 'nova'
  group 'nova'
  action :nothing
  subscribes :run, 'template[/etc/nova/nova.conf]', :immediately
end

apache_app 'placement' do
  cookbook 'osl-openstack'
  template 'wsgi-placement.conf.erb'
  notifies :reload, 'apache2_service[compute]', :immediately
end

apache_app 'nova-api' do
  cookbook 'osl-openstack'
  template 'wsgi-nova-api.conf.erb'
  notifies :reload, 'apache2_service[compute]', :immediately
end

apache_app 'nova-metadata' do
  cookbook 'osl-openstack'
  template 'wsgi-nova-metadata.conf.erb'
  notifies :reload, 'apache2_service[compute]', :immediately
end

apache2_service 'compute' do
  action :nothing
  subscribes :restart, 'delete_lines[remove dhcpbridge]'
  subscribes :restart, 'delete_lines[remove force_dhcp_release]'
  subscribes :reload, 'template[/etc/nova/nova.conf]'
end

%w(
  openstack-nova-conductor
  openstack-nova-consoleauth
  openstack-nova-novncproxy
  openstack-nova-scheduler
).each do |srv|
  service srv do
    action [:enable, :start]
    subscribes :restart, 'delete_lines[remove dhcpbridge]'
    subscribes :restart, 'delete_lines[remove force_dhcp_release]'
    subscribes :restart, 'template[/etc/nova/nova.conf]'
  end
end

certificate_manage 'novnc' do
  cert_path '/etc/nova/pki'
  cert_file 'novnc.pem'
  key_file  'novnc.key'
  chain_file 'novnc-bundle.crt'
  nginx_cert true
  owner 'nova'
  group 'nova'
  notifies :restart, 'service[openstack-nova-novncproxy]'
end

template '/etc/sysconfig/openstack-nova-novncproxy' do
  source 'novncproxy.erb'
  variables(
    cert: '/etc/nova/pki/certs/novnc.pem',
    key: '/etc/nova/pki/private/novnc.key'
  )
  notifies :restart, 'service[openstack-nova-novncproxy]'
end
