#
# Cookbook:: osl-openstack
# Recipe:: block_storage_common
#
# Copyright:: 2023-2025, Oregon State University
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
b = s['block-storage']
auth_endpoint = s['identity']['endpoint']

include_recipe 'osl-ceph'

package 'openstack-cinder'

template '/etc/cinder/cinder.conf' do
  owner 'root'
  group 'cinder'
  mode '0640'
  sensitive true
  variables(
    auth_endpoint: auth_endpoint,
    backup_ceph_pool: b['ceph']['backup_ceph_pool'],
    backup_ceph_user: b['ceph']['block_backup_rbd_store_user'],
    block_rbd_pool: b['ceph']['block_rbd_pool'],
    block_ssd_rbd_pool: b['ceph']['block_ssd_rbd_pool'],
    compute_pass: s['compute']['service']['pass'],
    database_connection: openstack_database_connection('block-storage'),
    image_endpoint: s['image']['endpoint'],
    memcached_endpoint: s['memcached']['endpoint'],
    region: b['region'],
    rbd_secret_uuid: ceph_fsid,
    rbd_user: b['ceph']['rbd_store_user'],
    service_pass: b['service']['pass'],
    transport_url: openstack_transport_url
  )
end
