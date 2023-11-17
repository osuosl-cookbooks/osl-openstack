#
# Cookbook:: osl-openstack
# Recipe:: block_storage
#
# Copyright:: 2015-2023, Oregon State University
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

osl_repos_openstack 'block-storage-controller'
osl_openstack_client 'block-storage-controller'
osl_firewall_openstack 'block-storage-controller'

include_recipe 'osl-openstack::block_storage_common'
include_recipe 'osl-openstack::_block_ceph' if node['osl-openstack']['ceph']['volume']

service 'openstack-cinder-volume' do
  action [:enable, :start]
end
