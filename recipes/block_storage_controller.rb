#
# Cookbook:: osl-openstack
# Recipe:: block_storage_controller
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

include_recipe 'openstack-block-storage::api'
include_recipe 'openstack-block-storage::scheduler'
include_recipe 'openstack-block-storage::identity_registration'

replace_or_add 'log-dir controller' do
  path '/usr/share/cinder/cinder-dist.conf'
  pattern '^logdir.*'
  line 'log-dir = /var/log/cinder'
  backup true
  replace_only true
  notifies :restart, 'service[apache2]'
  notifies :restart, 'service[cinder-scheduler]'
end
