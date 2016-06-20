#
# Cookbook Name:: osl-openstack
# Recipe:: linuxbridge
#
# Copyright (C) 2015-2016 Oregon State University
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
include_recipe 'osl-openstack'
include_recipe 'openstack-network'

node_type = node['osl-openstack']['node_type']
int_mappings = []
node['osl-openstack']['physical_interface_mappings'].each do |int|
  int_mappings.push("#{int['name']}:#{int[node_type]}")
end

node.default['openstack']['network']['plugins']['linuxbridge']['conf']
  .tap do |conf|
  conf['linux_bridge']['physical_interface_mappings'] = int_mappings.join(',')
end

include_recipe 'openstack-network::ml2_linuxbridge'
