#
# Cookbook:: osl-openstack
# Recipe:: block_storage_controller
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

osl_openstack_client 'block-storage-controller' do
  firewall true
end

s = os_secrets
b = s['block-storage']

include_recipe 'osl-apache'
include_recipe 'osl-apache::mod_proxy_uwsgi'

osl_openstack_service_user b['service']['user'] do
  password b['service']['pass']
end

%w(v2 v3).each do |v|
  osl_openstack_api "cinder#{v}" do
    type "volume#{v}"
    endpoint_name "volume#{v}"
    url "http://#{b['endpoint']}:8776/#{v}/%(project_id)s"
    region b['region']
  end
end

include_recipe 'osl-openstack::block_storage_common'

execute 'cinder: db_sync' do
  command 'cinder-manage db sync'
  user 'cinder'
  group 'cinder'
  only_if { openstack_db_node? }
  action :nothing
  subscribes :run, 'template[/etc/cinder/cinder.conf]', :immediately
end

openstack_db_sync_on_upgrade('cinder', 'osuosl-openstack-cinder', ['cinder: db_sync'])

directory openstack_uwsgi_cache_dir('cinder-api') do
  owner 'cinder'
  group 'cinder'
  mode '0750'
end

template '/etc/cinder/cinder-api-uwsgi.ini' do
  source 'uwsgi.ini.erb'
  group 'cinder'
  mode '0640'
  variables(
    chdir: openstack_venv('cinder'),
    wsgi_file: "#{openstack_venv('cinder')}/bin/cinder-wsgi",
    socket: '/run/cinder/api-uwsgi.sock',
    user: 'cinder',
    processes: 2,
    threads: 10,
    env: openstack_uwsgi_env('cinder-api')
  )
  notifies :restart, 'service[openstack-cinder-api]'
end

# uWSGI unit shipped by osuosl-openstack-cinder
service 'openstack-cinder-api' do
  action [:enable, :start]
  subscribes :restart, 'template[/etc/cinder/cinder.conf]'
end

apache_app 'cinder-api' do
  cookbook 'osl-openstack'
  server_address openstack_api_listen_ip
  template 'wsgi-api.conf.erb'
  template_params(port: 8776, socket: '/run/cinder/api-uwsgi.sock', log_name: 'cinder-api')
  notifies :reload, 'apache2_service[block_storage]', :immediately
end

apache2_service 'block_storage' do
  action :nothing
end

service 'openstack-cinder-scheduler' do
  action [:enable, :start]
  subscribes :restart, 'template[/etc/cinder/cinder.conf]'
end
