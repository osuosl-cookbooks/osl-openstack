#
# Cookbook:: osl-openstack
# Recipe:: ops_coordination
#
# Copyright:: 2026, Oregon State University
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
s = os_secrets['coordination']

osl_openstack_coordination 'default' do
  pass s['pass']
  nodes s['endpoint'] if s['endpoint']
  primary s['primary'] if s['primary']
  service_name s['service_name'] if s['service_name']
  down_after_ms s['down_after_ms'] if s['down_after_ms']
  failover_timeout_ms s['failover_timeout_ms'] if s['failover_timeout_ms']
  config_version s['config_version'] if s['config_version']
end
