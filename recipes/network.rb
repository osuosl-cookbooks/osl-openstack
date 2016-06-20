#
# Cookbook Name:: osl-openstack
# Recipe:: network
#
# Copyright (C) 2016 Oregon State University
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
include_recipe 'firewall::openstack'
include_recipe 'openstack-network::identity_registration'
include_recipe 'openstack-network::ml2_core_plugin'
include_recipe 'openstack-network::ml2_linuxbridge'
include_recipe 'openstack-network'
include_recipe 'openstack-network::plugin_config'
include_recipe 'openstack-network::server'
include_recipe 'openstack-network::l3_agent'
include_recipe 'openstack-network::dhcp_agent'
include_recipe 'openstack-network::metadata_agent'