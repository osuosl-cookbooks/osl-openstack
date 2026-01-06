#
# Cookbook:: osl-openstack
# Recipe:: telemetry
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

osl_repos_openstack 'telemetry'
osl_openstack_client 'telemetry'
osl_firewall_openstack 'telemetry'

include_recipe 'osl-openstack::telemetry_common'

package 'openstack-ceilometer-compute'

service 'openstack-ceilometer-compute' do
  action [:enable, :start]
  subscribes :restart, 'template[/etc/ceilometer/ceilometer.conf]'
  subscribes :restart, 'template[/etc/ceilometer/pipeline.yaml]'
  subscribes :restart, 'cookbook_file[/etc/ceilometer/polling.yaml]'
end
