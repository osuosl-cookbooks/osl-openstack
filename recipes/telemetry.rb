#
# Cookbook Name:: osl-openstack
# Recipe:: telemetry
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
include_recipe 'openstack-telemetry::gnocchi_install'

group 'ceph-telemetry' do
  group_name 'ceph'
  append true
  members %w(gnocchi)
  action :modify
  notifies :restart, 'service[gnocchi-metricd]', :immediately
end

secrets = openstack_credential_secrets

template "/etc/ceph/ceph.client.#{node['osl-openstack']['telemetry-metric']['rbd_store_user']}.keyring" do
  source 'ceph.client.keyring.erb'
  owner node['ceph']['owner']
  group node['ceph']['group']
  sensitive true
  variables(
    ceph_user: node['osl-openstack']['telemetry-metric']['rbd_store_user'],
    ceph_token: secrets['ceph']['metrics_token']
  )
  not_if { secrets['ceph']['metrics_token'].nil? }
  notifies :restart, 'service[gnocchi-metricd]'
end

# This file for some reason is set 640 which breaks gnocchi
file '/usr/share/gnocchi/gnocchi-dist.conf' do
  mode '0644'
end

include_recipe 'openstack-telemetry::gnocchi_configure'
include_recipe 'openstack-telemetry::agent-central'
include_recipe 'openstack-telemetry::agent-notification'
include_recipe 'openstack-telemetry::identity_registration'

# Ensure we run this as the ceph group so that is can access /etc/ceph/ceph.conf
edit_resource(:execute, 'run gnocchi-upgrade') do
  group 'ceph'
end

# Use our local version which has proper support for wsgi+keystone
edit_resource(:cookbook_file, File.join(node['openstack']['telemetry-metric']['conf_dir'], 'api-paste.ini')) do
  source 'gnocchi/api-paste.ini'
  cookbook 'osl-openstack'
end
