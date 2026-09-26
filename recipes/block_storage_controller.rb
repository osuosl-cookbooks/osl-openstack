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
include_recipe 'osl-apache::mod_wsgi'

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
  action :nothing
  subscribes :run, 'template[/etc/cinder/cinder.conf]', :immediately
end

apache_app 'cinder-api' do
  cookbook 'osl-openstack'
  server_address openstack_api_listen_ip
  template 'wsgi-api.conf.erb'
  template_params(
    port: 8776, group: 'cinder-wsgi', processes: 2, threads: 10, user: 'cinder',
    script: '/usr/bin/cinder-wsgi', log_name: 'cinder-api'
  )
  notifies :reload, 'apache2_service[block_storage]', :immediately
end

apache2_service 'block_storage' do
  action :nothing
  subscribes :reload, 'template[/etc/cinder/cinder.conf]'
end

service 'openstack-cinder-scheduler' do
  action [:enable, :start]
  subscribes :restart, 'template[/etc/cinder/cinder.conf]'
end
