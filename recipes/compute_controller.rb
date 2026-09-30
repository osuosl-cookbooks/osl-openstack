#
# Cookbook:: osl-openstack
# Recipe:: compute_controller
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

osl_openstack_client 'compute' do
  firewall true
end

s = os_secrets
c = s['compute']
p = s['placement']
auth_endpoint = openstack_auth_endpoint

include_recipe 'osl-apache'
include_recipe 'osl-apache::mod_proxy_uwsgi'

osl_openstack_service_user p['service']['user'] do
  password p['service']['pass']
end

osl_openstack_service_user c['service']['user'] do
  password c['service']['pass']
end

osl_openstack_api 'placement' do
  type 'placement'
  endpoint_name 'placement'
  url "http://#{p['endpoint']}:8778"
  region c['region']
end

# nova-api shares the placement host in every cloud
osl_openstack_api 'nova' do
  type 'compute'
  endpoint_name 'compute'
  url "http://#{p['endpoint']}:8774/v2.1"
  region c['region']
end

package openstack_compute_controller_pkgs

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
    memcached_endpoint: openstack_memcached_servers,
    service_pass: p['service']['pass']
  )
  notifies :run, 'execute[placement: db_sync]', :immediately
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
  command "nova-manage cell_v2 map_cell0 --database_connection #{openstack_database_connection('compute_cell0')}"
  user 'nova'
  group 'nova'
  sensitive true
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

listen_ip = openstack_api_listen_ip

# nova's WSGI apps are eventlet-patched, so an idle worker never runs a green heartbeat;
# the environment overrides nova.conf's false, which the eventlet services need
nova_wsgi_env = { 'OS_OSLO_MESSAGING_RABBIT__HEARTBEAT_IN_PTHREAD' => 'true' }

# The uWSGI units ship in the RPMs; Apache proxies each vhost to its socket
{
  'placement' => {
    port: 8778, processes: 6, threads: 1, user: 'placement', venv: 'placement', script: 'placement-api',
    service: 'placement-uwsgi', ini: '/etc/placement/placement-uwsgi.ini', socket: '/run/placement/uwsgi.sock',
    log_name: 'placement', location_alias: '/placement-api', configs: %w(template[/etc/placement/placement.conf])
  },
  'nova-api' => {
    port: 8774, processes: 6, threads: 1, user: 'nova', venv: 'nova-controller', script: 'nova-api-wsgi',
    service: 'openstack-nova-api', ini: '/etc/nova/nova-api-uwsgi.ini', socket: '/run/nova/api-uwsgi.sock',
    log_name: 'nova-api', configs: openstack_nova_config_resources, env: nova_wsgi_env
  },
  'nova-metadata' => {
    port: 8775, processes: 6, threads: 1, user: 'nova', venv: 'nova-controller', script: 'nova-metadata-wsgi',
    service: 'openstack-nova-metadata', ini: '/etc/nova/nova-metadata-uwsgi.ini', socket: '/run/nova/metadata-uwsgi.sock',
    log_name: 'nova-metadata', configs: openstack_nova_config_resources, env: nova_wsgi_env
  },
}.each do |app, a|
  template a[:ini] do
    source 'uwsgi.ini.erb'
    group a[:user]
    mode '0640'
    variables(
      chdir: openstack_venv(a[:venv]),
      wsgi_file: "#{openstack_venv(a[:venv])}/bin/#{a[:script]}",
      socket: a[:socket],
      user: a[:user],
      processes: a[:processes],
      threads: a[:threads],
      env: a[:env]
    )
    notifies :restart, "service[#{a[:service]}]"
  end

  service a[:service] do
    action [:enable, :start]
    a[:configs].each { |r| subscribes :restart, r }
  end

  apache_app app do
    cookbook 'osl-openstack'
    server_address listen_ip
    template 'wsgi-api.conf.erb'
    template_params a.slice(:port, :socket, :log_name, :location_alias)
    notifies :reload, 'apache2_service[compute]', :immediately
  end
end

apache2_service 'compute' do
  action :nothing
end

%w(
  openstack-nova-conductor
  openstack-nova-novncproxy
  openstack-nova-scheduler
).each do |srv|
  service srv do
    action [:enable, :start]
    openstack_nova_config_resources.each { |r| subscribes :restart, r }
  end
end

# haproxy terminates novnc TLS in HA; single controllers keep --ssl_only
# with a local cert
unless openstack_tls_on_haproxy?
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
end

template '/etc/sysconfig/openstack-nova-novncproxy' do
  source 'novncproxy.erb'
  variables(
    cert: '/etc/nova/pki/certs/novnc.pem',
    key: '/etc/nova/pki/private/novnc.key',
    haproxy_tls: openstack_tls_on_haproxy?
  )
  notifies :restart, 'service[openstack-nova-novncproxy]'
end

cron_d 'nova-rowsflush' do
  minute 20
  hour 5
  user 'nova'
  command %W(
    nova-manage db archive_deleted_rows --max_rows 1000 --before `date --date='today - 90 days' +\\%F`
    --until-complete --all-cells 2>&1 | systemd-cat -t nova-rowsflush
  ).join(' ')
end

cron_d 'nova-rowspurge' do
  minute 20
  hour 6
  user 'nova'
  command %W(
    nova-manage db purge --before `date --date='today - 14 days' +\\%D`
    --all-cells 2>&1 | systemd-cat -t nova-rowspurge
  ).join(' ')
end

# Deploy Nova Flavor Sync script for ad-hoc RequestSpec fixes
cookbook_file '/root/nova-fix-flavors.py' do
  source 'fix-flavors.py'
  owner 'root'
  group 'root'
  mode '0700'
end

# Create backup directory for flavor sync
directory '/root/.nova-flavor-fixes/backups' do
  owner 'root'
  group 'root'
  mode '0700'
  recursive true
end

# Deploy cold migration script (host-to-host, e.g. across qemu/libvirt versions)
cookbook_file '/root/nova-cold-migrate-host.py' do
  source 'cold-migrate-host.py'
  owner 'root'
  group 'root'
  mode '0700'
end

# Deploy read-only audit for leftover resize/migration debris (snaps, contexts, volumes)
cookbook_file '/root/nova-resize-debris-check.py' do
  source 'resize-debris-check.py'
  owner 'root'
  group 'root'
  mode '0700'
end

# Deploy maintenance notice generator and its email templates
cookbook_file '/root/nova-maintenance-notice.py' do
  source 'maintenance-notice.py'
  owner 'root'
  group 'root'
  mode '0700'
end

remote_directory '/root/nova-maintenance-templates' do
  source 'maintenance-templates'
  owner 'root'
  group 'root'
  mode '0700'
  files_owner 'root'
  files_group 'root'
  files_mode '0600'
end
