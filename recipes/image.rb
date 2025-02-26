#
# Cookbook:: osl-openstack
# Recipe:: image
#
# Copyright:: 2016-2025, Oregon State University
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

osl_repos_openstack 'image'
osl_openstack_client 'image'
osl_openstack_openrc 'image'
osl_firewall_openstack 'image'

include_recipe 'osl-ceph' unless openstack_local_storage_image

s = os_secrets
i = s['image']
auth_endpoint = s['identity']['endpoint']

osl_openstack_user i['service']['user'] do
  domain_name 'default'
  role_name 'admin'
  project_name 'service'
  password i['service']['pass']
  action [:create, :grant_role]
end

osl_openstack_service 'glance' do
  type 'image'
end

%w(
  admin
  internal
  public
).each do |int|
  osl_openstack_endpoint "image-#{int}" do
    endpoint_name 'image'
    service_name 'glance'
    interface int
    url "http://#{i['endpoint']}:9292"
    region i['region']
  end
end

package 'openstack-glance'

template '/etc/glance/glance-api.conf' do
  owner 'root'
  group 'glance'
  mode '0640'
  sensitive true
  variables(
    auth_endpoint: auth_endpoint,
    database_connection: openstack_database_connection('image'),
    local_storage: openstack_local_storage_image,
    memcached_endpoint: s['memcached']['endpoint'],
    rbd_store_pool: safe_dig(i, 'ceph', 'rbd_store_pool'),
    rbd_store_user: safe_dig(i, 'ceph', 'rbd_store_user'),
    service_pass: i['service']['pass'],
    transport_url: openstack_transport_url
  )
  notifies :run, 'execute[glance: db_sync]', :immediately
  notifies :restart, 'service[openstack-glance-api]'
end

execute 'glance: db_sync' do
  command 'glance-manage db_sync'
  user 'glance'
  group 'glance'
  action :nothing
end

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
end
