#
# Cookbook:: osl-openstack
# Recipe:: telemetry_common
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

s = os_secrets
t = s['telemetry']
auth_endpoint = s['identity']['endpoint']

package 'openstack-ceilometer-common'

template '/etc/ceilometer/ceilometer.conf' do
  owner 'root'
  group 'ceilometer'
  mode '0640'
  sensitive true
  variables(
    auth_endpoint: auth_endpoint,
    memcached_endpoint: s['memcached']['endpoint'],
    service_pass: t['service']['pass'],
    transport_url: openstack_transport_url
  )
end

template '/etc/ceilometer/pipeline.yaml' do
  owner 'ceilometer'
  group 'ceilometer'
  mode '0640'
  variables(
    publishers: t['pipeline']['publishers']
  )
end

cookbook_file '/etc/ceilometer/polling.yaml' do
  owner 'ceilometer'
  group 'ceilometer'
  mode '0640'
end
