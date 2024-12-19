#
# Cookbook:: osl-openstack
# Recipe:: upgrade
#
# Copyright:: 2017-2024, Oregon State University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package 'crudini'

service 'yum-cron' do
  action [:stop, :disable]
  not_if { ::File.exist?('/root/upgrade-test') || ::File.exist?('/root/yoga-upgrade-done') }
end

service 'dnf-automatic.timer' do
  action [:stop, :disable]
  not_if { ::File.exist?('/root/upgrade-test') || ::File.exist?('/root/yoga-upgrade-done') }
end

osl_repos_openstack 'upgrade'
osl_firewall_openstack 'upgrade'

if node['osl-openstack']['node_type'] == 'controller'
  osl_firewall_memcached 'upgrade'
  osl_firewall_port 'amqp' do
    osl_only true
  end

  osl_firewall_port 'rabbitmq_mgt' do
    osl_only true
  end

  osl_firewall_port 'http' do
    ports %w(80 443)
  end
end

cookbook_file '/root/upgrade.sh' do
  source "upgrade-#{node['osl-openstack']['node_type']}.sh"
  mode '755'
end

ruby_block 'raise_upgrade_exeception' do
  block do
    raise 'Upgrade recipe enabled, stopping futher chef resources from running'
  end
  not_if { ::File.exist?('/root/upgrade-test') || ::File.exist?('/root/yoga-upgrade-done') }
end
