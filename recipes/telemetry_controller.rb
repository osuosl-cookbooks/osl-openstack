#
# Cookbook:: osl-openstack
# Recipe:: telemetry_controller
#
# Copyright:: 2023-2026, Oregon State University
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

osl_openstack_client 'telemetry-controller' do
  firewall true
end

s = os_secrets
t = s['telemetry']

osl_openstack_service_user t['service']['user'] do
  password t['service']['pass']
end

ceilometer_services = %w(openstack-ceilometer-central openstack-ceilometer-notification)

include_recipe 'osl-openstack::telemetry_common'

ceilometer_services.each do |srv|
  service srv do
    action [:enable, :start]
    openstack_ceilometer_config_resources.each { |r| subscribes :restart, r }
    subscribes :restart, 'package[osuosl-openstack-ceilometer]'
  end
end
