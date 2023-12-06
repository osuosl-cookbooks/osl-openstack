#
# Cookbook:: osl-openstack
# Recipe:: compute_common
#
# Copyright:: 2023, Oregon State University
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
c = s['compute']
auth_endpoint = s['identity']['endpoint']
compute = node['osl-openstack']['node_type'] == 'compute'

include_recipe 'osl-ceph'

delete_lines 'remove dhcpbridge' do
  path '/usr/share/nova/nova-dist.conf'
  pattern '^dhcpbridge.*'
  backup true
end

delete_lines 'remove force_dhcp_release' do
  path '/usr/share/nova/nova-dist.conf'
  pattern '^force_dhcp_release.*'
  backup true
end

template '/etc/nova/nova.conf' do
  owner 'root'
  group 'nova'
  mode '0640'
  sensitive true
  variables(
    api_database_connection: openstack_database_connection('compute_api'),
    allow_resize_to_same_host: c['allow_resize_to_same_host'],
    auth_endpoint: auth_endpoint,
    cpu_allocation_ratio: c['cpu_allocation_ratio'],
    compute: compute,
    database_connection: openstack_database_connection('compute'),
    disk_allocation_ratio: c['disk_allocation_ratio'],
    endpoint: c['endpoint'],
    enabled_filters: c['enabled_filters'],
    image_endpoint: s['image']['endpoint'],
    images_rbd_pool: c['ceph']['images_rbd_pool'],
    local_storage: openstack_local_storage,
    memcached_endpoint: s['memcached']['endpoint'],
    metadata_proxy_shared_secret: s['network']['metadata_proxy_shared_secret'],
    neutron_pass: s['network']['service']['pass'],
    placement_pass: s['placement']['service']['pass'],
    pci_alias: openstack_pci_alias,
    pci_passthrough_whitelist: openstack_pci_passthrough_whitelist,
    rbd_secret_uuid: ceph_fsid,
    rbd_user: c['ceph']['rbd_user'],
    service_pass: c['service']['pass'],
    transport_url: openstack_transport_url
  )
end
