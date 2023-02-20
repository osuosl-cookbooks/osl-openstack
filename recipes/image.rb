#
# Cookbook:: osl-openstack
# Recipe:: image
#
# Copyright:: 2016-2023, Oregon State University
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

osl_firewall_openstack 'osl-openstack'

include_recipe 'openstack-image::api'
include_recipe 'openstack-image::identity_registration'

if node['osl-openstack']['ceph']['image']
  secrets = openstack_credential_secrets

  group 'ceph-image' do
    group_name 'ceph'
    append true
    members %w(glance)
    action :modify
    notifies :restart, 'service[glance-api]', :immediately
  end

  template "/etc/ceph/ceph.client.#{node['osl-openstack']['image']['rbd_store_user']}.keyring" do
    source 'ceph.client.keyring.erb'
    owner node['ceph']['owner']
    group node['ceph']['group']
    sensitive true
    variables(
      ceph_user: node['osl-openstack']['image']['rbd_store_user'],
      ceph_token: secrets['ceph']['image_token']
    )
    not_if { secrets['ceph']['image_token'].nil? }
    notifies :restart, 'service[glance-api]'
  end
end

include_recipe 'openstack-image::image_upload'
