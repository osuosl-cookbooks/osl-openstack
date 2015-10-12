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
vnc_bind_int = node['osl-openstack']['vnc_bind_interface']['controller']
node.default['openstack']['endpoints']['compute-vnc-bind']['bind_interface'] =
  vnc_bind_int

include_recipe 'osl-apache::default'
include_recipe 'firewall::openstack'
include_recipe 'firewall::amqp'
include_recipe 'firewall::vnc'
include_recipe 'osl-openstack::_fedora'
include_recipe 'osl-openstack::default'
include_recipe 'openstack-ops-messaging::server'
include_recipe 'openstack-identity::server'
include_recipe 'openstack-identity::registration'
include_recipe 'openstack-image::api'
include_recipe 'openstack-image::registry'
include_recipe 'openstack-image::identity_registration'
include_recipe 'openstack-image::image_upload'
include_recipe 'openstack-network::identity_registration'
include_recipe 'openstack-network::openvswitch'
include_recipe 'openstack-network::l3_agent'
include_recipe 'openstack-network::dhcp_agent'
include_recipe 'openstack-network::metadata_agent'
include_recipe 'openstack-network::server'
include_recipe 'openstack-compute::nova-setup'
include_recipe 'openstack-compute::identity_registration'
include_recipe 'openstack-compute::conductor'
include_recipe 'openstack-compute::scheduler'
include_recipe 'openstack-compute::api-ec2'
include_recipe 'openstack-compute::api-os-compute'
include_recipe 'openstack-block-storage::api'
include_recipe 'openstack-block-storage::scheduler'
include_recipe 'openstack-block-storage::volume'
include_recipe 'certificate::wildcard'
include_recipe 'openstack-compute::nova-cert'
include_recipe 'openstack-compute::vncproxy'
include_recipe 'osl-openstack::novnc'
include_recipe 'openstack-dashboard::server'
