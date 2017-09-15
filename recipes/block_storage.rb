#
# Cookbook Name:: osl-openstack
# Recipe:: block_storage
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
iscsi_hosts = ['127.0.0.1']
iscsi_hosts += node['osl-openstack']['cinder']['iscsi_ips']
iscsi_role = node['osl-openstack']['cinder']['iscsi_role']
if (iscsi_role && !Chef::Config[:solo]) || defined?(ChefSpec)
  search(:node, "role:#{iscsi_role}") do |n| # ~FC003
    iscsi_hosts << n['ipaddress']
  end
end

node.override['firewall']['range']['iscsi']['4'] = iscsi_hosts

# Missing package dep
package 'python2-crypto'

include_recipe 'firewall::iscsi'
include_recipe 'osl-openstack'
include_recipe 'openstack-block-storage::volume'
include_recipe 'openstack-block-storage::identity_registration'
