#
# Cookbook Name:: osl-openstack
# Recipe:: dashboard
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
include_recipe 'memcached'
include_recipe 'certificate::wildcard'
include_recipe 'openstack-dashboard::horizon'

# Workaround for [1] which should be merged in the N release
# [1] https://review.openstack.org/#/c/307859/
secret_lock_file =
  ::File.join(node['openstack']['dashboard']['django_path'],
              'openstack_dashboard',
              'local',
              '_usr_share_openstack-dashboard_openstack_dashboard_local_.' \
              'secret_key_store.lock')

secret_file =
  ::File.join(node['openstack']['dashboard']['django_path'],
              'openstack_dashboard',
              'local',
              '.secret_key_store')

file secret_lock_file do
  owner 'root'
  group node['openstack']['dashboard']['horizon_user']
  mode 0660
  subscribes :create, 'service[apache2]', :immediately
  only_if { ::File.exist?(secret_lock_file) }
end

file secret_file do
  owner node['openstack']['dashboard']['horizon_user']
  group node['openstack']['dashboard']['horizon_user']
  mode 0600
  subscribes :create, 'service[apache2]', :immediately
  only_if { ::File.exist?(secret_file) }
end
