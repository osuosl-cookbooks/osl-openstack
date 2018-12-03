#
# Cookbook Name:: osl-openstack
# Recipe:: identity
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
include_recipe 'osl-openstack::ops_messaging'
include_recipe 'firewall::openstack'
include_recipe 'certificate::wildcard'
include_recipe 'openstack-identity::server-apache'
include_recipe 'openstack-identity::registration'

# Clear lock file when notified
execute 'Clear Keystone apache restart' do
  command "rm -f #{Chef::Config[:file_cache_path]}/keystone-apache-restarted"
  action :nothing
end

# Whenever a keystone config is updated, have it notify the resource which clears the lock so the service can be
# restarted.
%w(
  /etc/keystone/keystone.conf
  /etc/keystone/keystone-paste.ini
  /etc/httpd/sites-available/keystone-admin.conf
  /etc/httpd/sites-available/keystone-main.conf
).each do |t|
  edit_resource(:template, t) do
    notifies :run, 'execute[Clear Keystone apache restart]', :immediately
  end
end

# Only restart Keystone apache during the initial install. This causes monitoring and service issues while the service
# is restarted.
edit_resource(:execute, 'Keystone apache restart') do
  command "touch #{Chef::Config[:file_cache_path]}/keystone-apache-restarted"
  creates "#{Chef::Config[:file_cache_path]}/keystone-apache-restarted"
end
