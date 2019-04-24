#
# Cookbook:: osl-openstack
# Recipe:: container
#
# Copyright:: 2019, Oregon State University
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
docker_hosts = %w(127.0.0.1)
search(:node, "role:#{node['osl-openstack']['cluster_role']}") do |n|
  docker_hosts << n['ipaddress']
end

node.default['firewall']['docker']['range']['4'] = docker_hosts.sort.uniq
node.default['osl-docker']['client_only'] = true

include_recipe 'osl-openstack'
include_recipe 'firewall::openstack'
include_recipe 'firewall::docker'
include_recipe 'osl-docker::nvidia'
include_recipe 'openstack-container::compute'
include_recipe 'openstack-container::network'
