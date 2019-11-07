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
include_recipe 'openstack-telemetry::agent-central'
include_recipe 'openstack-telemetry::agent-notification'
include_recipe 'openstack-telemetry::identity_registration'

# TODO: Remove the following after this converges on nodes
platform = node['openstack']['telemetry']['platform']

service 'gnocchi-metricd' do
  service_name platform['gnocchi-metricd_service']
  action [:stop, :disable]
end

%w(enabled available).each do |dir|
  file "/etc/httpd/sites-#{dir}/gnocchi-api.conf" do
    notifies :restart, 'service[apache2]'
    manage_symlink_source true
    action :delete
  end
end

gnocchi_packages = platform['gnocchi_packages'] + %w(gnocchi-common python-gnocchi)

package gnocchi_packages do
  action :remove
end
