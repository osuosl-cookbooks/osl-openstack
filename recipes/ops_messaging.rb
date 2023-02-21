#
# Cookbook:: osl-openstack
# Recipe:: ops_messaging
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

osl_firewall_port 'amqp' do
  osl_only true
end

osl_firewall_port 'rabbitmq_mgt' do
  osl_only true
end

include_recipe 'openstack-ops-messaging::rabbitmq-server'
