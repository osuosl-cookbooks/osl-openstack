#
# Cookbook:: osl-openstack
# Recipe:: upgrade
#
# Copyright:: 2017-2020, Oregon State University
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
yum_repository 'RDO-rocky' do
  action :delete
end

include_recipe 'osl-openstack'

if node['osl-openstack']['node_type'] == 'controller'
  db_user = node['openstack']['db']['compute_cell0']['username']
  db_password = get_password('db', 'nova_cell0')
  uri = db_uri('compute_cell0', db_user, db_password)

  file '/root/nova-cell-db-uri' do
    content uri
    mode '600'
    sensitive true
  end
end

### Stein Upgrade
# TODO: Remove after Stein

nova_api_pass = get_password 'db', 'nova_api'
placement_user = node['openstack']['db']['placement']['username']
placement_pass = get_password 'db', 'placement'
placement_db_uri = db_uri('placement', placement_user, placement_pass)

template '/root/migrate-db.rc' do
  mode '600'
  sensitive true
  variables(
    nova_api_pass: nova_api_pass,
    placement_pass: placement_pass
  )
end

package 'openstack-placement-common'

replace_or_add 'placement db' do
  path '/etc/placement/placement.conf'
  pattern /^#connection = <None>/
  line "connection = #{placement_db_uri}"
  replace_only true
end

###

cookbook_file '/root/upgrade.sh' do
  source "upgrade-#{node['osl-openstack']['node_type']}.sh"
  mode '755'
end

ruby_block 'raise_upgrade_exeception' do
  block do
    raise 'Upgrade recipe enabled, stopping futher chef resources from running'
  end
  not_if { ::File.exist?('/root/upgrade-test') || ::File.exist?('/root/rocky-upgrade-done') }
end
