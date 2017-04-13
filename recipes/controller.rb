#
# Cookbook Name:: osl-openstack
# Recipe:: controller
#
# Copyright (C) 2014, 2015 Oregon State University
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
node.default['osl-openstack']['node_type'] = 'controller'

include_recipe 'osl-apache::default'
include_recipe 'firewall::openstack'
include_recipe 'firewall::memcached'
include_recipe 'firewall::vnc'
include_recipe 'osl-openstack::default'
include_recipe 'memcached'
include_recipe 'osl-openstack::identity'
include_recipe 'osl-openstack::image'
include_recipe 'osl-openstack::network' unless node['osl-openstack']['separate_network_node']
include_recipe 'osl-openstack::compute_controller'
include_recipe 'osl-openstack::block_storage_controller'
include_recipe 'osl-openstack::telemetry'
include_recipe 'osl-openstack::dashboard'
include_recipe 'osl-openstack::mon'
