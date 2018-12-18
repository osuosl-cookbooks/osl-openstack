#
# Cookbook:: osl-openstack
# Recipe:: upgrade
#
# Copyright:: 2017, Oregon State University
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
yum_repository 'RDO-newton' do
  action :delete
end

include_recipe 'osl-openstack'

if node['osl-openstack']['node_type'] == 'controller'
  # include the recipe to setup fernet tokens
  include_recipe 'openstack-identity::_fernet_tokens'

  db_user = node['openstack']['db']['compute_cell0']['username']
  db_password = get_password('db', 'nova_cell0')
  uri = db_uri('compute_cell0', db_user, db_password)

  file '/root/nova-cell-db-uri' do
    content uri
    mode '600'
    sensitive true
  end
end

cookbook_file '/root/upgrade.sh' do
  source "upgrade-#{node['osl-openstack']['node_type']}.sh"
  mode 0755
end

ruby_block 'raise_upgrade_exeception' do
  block do
    raise 'Upgrade recipe enabled, stopping futher chef resources from running'
  end
  not_if { ::File.exist?('/root/upgrade-test') || ::File.exist?('/root/ocata-upgrade-done') }
end
