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
int_mappings = []
node['osl-openstack']['physical_interface_mappings'].each do |int|
  int_mappings.push("#{int['name']}:#{int['controller']}")
end

node.default['openstack']['network']['plugins']['linuxbridge'].tap do |conf|
  conf['conf']['linux_bridge']['physical_interface_mappings'] =
    int_mappings.join(',')
end

include_recipe 'osl-apache::default'
include_recipe 'firewall::openstack'
include_recipe 'firewall::memcached'
include_recipe 'firewall::vnc'
include_recipe 'osl-openstack::default'
include_recipe 'memcached'
include_recipe 'osl-openstack::identity'
include_recipe 'osl-openstack::image'
include_recipe 'osl-openstack::network'
include_recipe 'openstack-compute::nova-setup'
include_recipe 'openstack-compute::conductor'
include_recipe 'openstack-compute::scheduler'
include_recipe 'openstack-compute::api-os-compute'
include_recipe 'openstack-compute::api-metadata'
include_recipe 'openstack-compute::nova-cert'
include_recipe 'openstack-compute::vncproxy'
include_recipe 'openstack-compute::identity_registration'
include_recipe 'openstack-block-storage::api'
include_recipe 'openstack-block-storage::scheduler'
include_recipe 'openstack-block-storage::identity_registration'
# include_recipe 'openstack-telemetry::identity_registration'
# include_recipe 'openstack-telemetry::agent-central'
# include_recipe 'openstack-telemetry::agent-notification'
# include_recipe 'openstack-telemetry::alarm-evaluator'
# include_recipe 'openstack-telemetry::alarm-notifier'
# include_recipe 'openstack-telemetry::collector'
# include_recipe 'openstack-telemetry::api'
# include_recipe 'certificate::wildcard'
# include_recipe 'osl-openstack::novnc'
# include_recipe 'openstack-bare-metal::api'
# include_recipe 'openstack-bare-metal::identity_registration'
# include_recipe 'openstack-orchestration::engine'
# include_recipe 'openstack-orchestration::api'
# include_recipe 'openstack-orchestration::api-cfn'
# include_recipe 'openstack-orchestration::api-cloudwatch'
# include_recipe 'openstack-orchestration::identity_registration'
include_recipe 'openstack-dashboard::server'

# XXX: Temporary workaround for https://bugs.launchpad.net/bugs/1496158
file ::File.join(node['openstack']['dashboard']['django_path'],
                 'openstack_dashboard',
                 'local',
                 '_usr_share_openstack-dashboard_openstack_dashboard_local_.' \
                 'secret_key_store.lock') do
  mode 0774
end
