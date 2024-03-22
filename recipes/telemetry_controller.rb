#
# Cookbook:: osl-openstack
# Recipe:: telemetry_controller
#
# Copyright:: 2023-2024, Oregon State University
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

osl_repos_openstack 'telemetry-controller'
osl_openstack_client 'telemetry-controller'
osl_firewall_openstack 'telemetry-controller'

s = os_secrets
t = s['telemetry']

osl_openstack_user t['service']['user'] do
  domain_name 'default'
  role_name 'admin'
  project_name 'service'
  password t['service']['pass']
  action [:create, :grant_role]
end

package %w(
  openstack-ceilometer-central
  openstack-ceilometer-notification
)

include_recipe 'osl-openstack::telemetry_common'

%w(
  openstack-ceilometer-central
  openstack-ceilometer-notification
).each do |srv|
  service srv do
    action [:enable, :start]
    subscribes :restart, 'template[/etc/ceilometer/ceilometer.conf]'
    subscribes :restart, 'template[/etc/ceilometer/pipeline.yaml]'
    subscribes :restart, 'cookbook_file[/etc/ceilometer/polling.yaml]'
  end
end

# TODO: Apply upstream patch which fixes [1] use with prometheus
# [1] https://review.opendev.org/686368
package 'patch'

cookbook_file ::File.join(Chef::Config[:file_cache_path], 'ceilometer-prometheus1.patch')
cookbook_file ::File.join(Chef::Config[:file_cache_path], 'ceilometer-prometheus2.patch')

execute "patch -p1 < #{::File.join(Chef::Config[:file_cache_path], 'ceilometer-prometheus1.patch')}" do
  cwd "#{openstack_python_lib}/site-packages"
  notifies :restart, 'service[openstack-ceilometer-central]'
  notifies :restart, 'service[openstack-ceilometer-notification]'
  not_if "grep -q curated_sname #{openstack_python_lib}/site-packages/ceilometer/publisher/prometheus.py"
end

execute "patch -p1 < #{::File.join(Chef::Config[:file_cache_path], 'ceilometer-prometheus2.patch')}" do
  cwd "#{openstack_python_lib}/site-packages"
  notifies :restart, 'service[openstack-ceilometer-central]'
  notifies :restart, 'service[openstack-ceilometer-notification]'
  not_if "grep -q s.project_id #{openstack_python_lib}/site-packages/ceilometer/publisher/prometheus.py"
end
