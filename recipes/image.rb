#
# Cookbook:: osl-openstack
# Recipe:: image
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

osl_openstack_client 'image' do
  firewall true
  openrc true
end

include_recipe 'osl-ceph' unless openstack_local_storage_image

s = os_secrets
i = s['image']
auth_endpoint = openstack_auth_endpoint

osl_openstack_service_user i['service']['user'] do
  password i['service']['pass']
end

osl_openstack_api 'glance' do
  type 'image'
  endpoint_name 'image'
  url "http://#{i['endpoint']}:9292"
  region i['region']
end

package 'osuosl-openstack-glance' do
  action :upgrade
end

template '/etc/glance/glance-api.conf' do
  owner 'root'
  group 'glance'
  mode '0640'
  sensitive true
  variables(
    auth_endpoint: auth_endpoint,
    database_connection: openstack_database_connection('image'),
    listen_ip: openstack_api_listen_ip,
    local_storage: openstack_local_storage_image,
    memcached_endpoint: openstack_memcached_servers,
    rbd_store_pool: safe_dig(i, 'ceph', 'rbd_store_pool'),
    rbd_store_user: safe_dig(i, 'ceph', 'rbd_store_user'),
    service_pass: i['service']['pass'],
    **openstack_messaging_template_vars
  )
  notifies :run, 'execute[glance: db_sync]', :immediately
  notifies :restart, 'service[openstack-glance-api]'
end

execute 'glance: db_sync' do
  command 'glance-manage db_sync'
  user 'glance'
  group 'glance'
  only_if { openstack_db_node? }
  action :nothing
end

openstack_db_sync_on_upgrade('glance', 'osuosl-openstack-glance', ['glance: db_sync'])

group 'ceph-image' do
  group_name 'ceph'
  append true
  members %w(glance)
  action :modify
  notifies :restart, 'service[openstack-glance-api]', :immediately
end unless openstack_local_storage_image

osl_ceph_keyring i['ceph']['rbd_store_user'] do
  key i['ceph']['image_token']
  not_if { i['ceph']['image_token'].nil? }
  notifies :restart, 'service[openstack-glance-api]'
end unless openstack_local_storage_image

service 'openstack-glance-api' do
  action [:enable, :start]
  subscribes :restart, 'package[osuosl-openstack-glance]'
end
