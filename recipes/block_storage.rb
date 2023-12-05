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

osl_repos_openstack 'block-storage'
osl_openstack_client 'block-storage'
osl_firewall_openstack 'block-storage'

s = os_secrets['block-storage']['ceph']
include_recipe 'osl-openstack::block_storage_common'

group 'ceph-block' do
  group_name 'ceph'
  append true
  members %w(cinder)
  action :modify
  notifies :restart, 'service[openstack-cinder-volume]', :immediately
end

osl_ceph_keyring s['rbd_store_user'] do
  key s['block_token']
  not_if { s['block_token'].nil? }
  notifies :restart, 'service[openstack-cinder-volume]', :immediately
end

osl_ceph_keyring s['block_backup_rbd_store_user'] do
  key s['block_backup_token']
  not_if { s['block_backup_token'].nil? }
end

service 'openstack-cinder-volume' do
  action [:enable, :start]
  subscribes :restart, 'template[/etc/cinder/cinder.conf]'
end
