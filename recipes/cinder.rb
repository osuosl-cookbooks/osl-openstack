#
# Cookbook Name:: osl-openstack
# Recipe:: cinder
#
# Copyright (C) 2015 Oregon State University
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
# this is required because of the fedora deps. Will be fixed once its moved into
# a _common recipe.
iscsi_hosts = ['127.0.0.1']
iscsi_role = node['osl-openstack']['cinder']['iscsi_role']
unless iscsi_role.nil?
  search(:node, "role:#{iscsi_role}") do |i|
    iscsi_hosts << i['ipaddress']
  end
end

node.override['firewall']['range']['iscsi'] = iscsi_hosts

include_recipe 'firewall'
include_recipe 'firewall::openstack'
include_recipe 'firewall::iscsi'
include_recipe 'osl-openstack::default'
include_recipe 'osl-openstack::_fedora' if platform?('fedora')
include_recipe 'openstack-block-storage::api'
include_recipe 'openstack-block-storage::scheduler'
include_recipe 'openstack-block-storage::volume'
include_recipe 'openstack-block-storage::client'
include_recipe 'openstack-block-storage::identity_registration'
