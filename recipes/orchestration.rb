#
# Cookbook:: osl-openstack
# Recipe:: orchestration
#
# Copyright:: 2017-2024, Oregon State University
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
osl_repos_openstack 'orchestration'
osl_openstack_client 'orchestration'
osl_firewall_openstack 'orchestration'

s = os_secrets
o = s['orchestration']
auth_endpoint = s['identity']['endpoint']

osl_openstack_user o['service']['user'] do
  domain_name 'default'
  role_name 'admin'
  project_name 'service'
  password o['service']['pass']
  action [:create, :grant_role]
end

osl_openstack_service 'heat' do
  type 'orchestration'
end

osl_openstack_service 'heat-cfn' do
  type 'cloudformation'
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

%w(
  admin
  internal
  public
).each do |int|
  osl_openstack_endpoint "orchestration-#{int}" do
    endpoint_name 'orchestration'
    service_name 'heat'
    interface int
    url "http://#{o['endpoint']}:8004/v1/%\(tenant_id\)s"
    region 'RegionOne'
  end

  osl_openstack_endpoint "cloudformation-#{int}" do
    endpoint_name 'cloudformation'
    service_name 'heat-cfn'
    interface int
    url "http://#{o['endpoint']}:8000/v1"
    region 'RegionOne'
  end
end

package %w(
  openstack-heat-api
  openstack-heat-api-cfn
  openstack-heat-engine
)

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
    memcached_endpoint: s['memcached']['endpoint'],
    service_pass: o['service']['pass'],
    transport_url: openstack_transport_url
  )
  notifies :run, 'execute[heat: db_sync]', :immediately
end

execute 'heat: db_sync' do
  command 'heat-manage db_sync'
  user 'heat'
  group 'heat'
  action :nothing
end

%w(
  openstack-heat-api
  openstack-heat-api-cfn
  openstack-heat-engine
).each do |srv|
  service srv do
    action [:enable, :start]
    subscribes :restart, 'template[/etc/heat/heat.conf]'
  end
end
