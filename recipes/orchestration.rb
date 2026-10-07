#
# Cookbook:: osl-openstack
# Recipe:: orchestration
#
# Copyright:: 2017-2026, Oregon State University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
osl_openstack_client 'orchestration' do
  firewall true
end

s = os_secrets
o = s['orchestration']
auth_endpoint = openstack_auth_endpoint

osl_openstack_service_user o['service']['user'] do
  password o['service']['pass']
end

osl_openstack_domain 'heat'

osl_openstack_user 'heat_domain_admin' do
  domain_name 'heat'
  role_name 'admin'
  password o['heat_domain_admin']
  action [:create, :grant_domain]
end

osl_openstack_role 'heat_stack_owner'
osl_openstack_role 'heat_stack_user'

# Heat's endpoints were registered in RegionOne regardless of the bag region
osl_openstack_api 'heat' do
  type 'orchestration'
  endpoint_name 'orchestration'
  url "http://#{o['endpoint']}:8004/v1/%(tenant_id)s"
  region 'RegionOne'
end

osl_openstack_api 'heat-cfn' do
  type 'cloudformation'
  endpoint_name 'cloudformation'
  url "http://#{o['endpoint']}:8000/v1"
  region 'RegionOne'
end

heat_services = %w(openstack-heat-api openstack-heat-api-cfn openstack-heat-engine)

package 'osuosl-openstack-heat' do
  action :upgrade
end

template '/etc/heat/heat.conf' do
  owner 'root'
  group 'heat'
  mode '0640'
  sensitive true
  variables(
    auth_encryption_key: o['auth_encryption_key'],
    auth_endpoint: auth_endpoint,
    database_connection: openstack_database_connection('orchestration'),
    endpoint: o['endpoint'],
    heat_domain_admin: o['heat_domain_admin'],
    listen_ip: openstack_api_listen_ip,
    memcached_endpoint: openstack_memcached_servers,
    region: o['region'],
    service_pass: o['service']['pass'],
    **openstack_messaging_template_vars
  )
  notifies :run, 'execute[heat: db_sync]', :immediately
end

execute 'heat: db_sync' do
  command 'heat-manage db_sync'
  user 'heat'
  group 'heat'
  action :nothing
end

heat_services.each do |srv|
  service srv do
    action [:enable, :start]
    subscribes :restart, 'template[/etc/heat/heat.conf]'
  end
end
