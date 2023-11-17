#
# Cookbook:: osl-openstack
# Recipe:: block_storage_controller
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

osl_repos_openstack 'block-storage-controller'
osl_openstack_client 'block-storage-controller'
osl_firewall_openstack 'block-storage-controller'

s = os_secrets
b = s['block-storage']

include_recipe 'osl-apache'
include_recipe 'osl-apache::mod_wsgi'

osl_openstack_user b['service']['user'] do
  domain_name 'default'
  role_name 'admin'
  project_name 'service'
  password b['service']['pass']
  action [:create, :grant_role]
end

osl_openstack_service 'cinderv2' do
  type 'volumev2'
end

osl_openstack_service 'cinderv3' do
  type 'volumev3'
end

%w(
  admin
  internal
  public
).each do |int|
  osl_openstack_endpoint "volumev2-#{int}" do
    endpoint_name 'volumev2'
    service_name 'cinderv2'
    interface int
    url "http://#{b['endpoint']}:8776/v2/%(project_id)s"
    region 'RegionOne'
  end

  osl_openstack_endpoint "volumev3-#{int}" do
    endpoint_name 'volumev3'
    service_name 'cinderv3'
    interface int
    url "http://#{b['endpoint']}:8776/v3/%(project_id)s"
    region 'RegionOne'
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
  template 'wsgi-cinder-api.conf.erb'
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
