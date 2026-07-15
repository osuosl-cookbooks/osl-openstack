#
# Cookbook:: osl-openstack
# Recipe:: mon
#
# Copyright:: 2014-2026, Oregon State University
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

include_recipe 'osl-nrpe'

s = os_secrets

# Increase load threshold on openpower nodes (double the default values)
if node['kernel']['machine'] == 'ppc64le'
  total_cpu = node['cpu']['total']
  r = resources(nrpe_check: 'check_load')
  r.warning_condition = "#{total_cpu * 5 + 10},#{total_cpu * 5 + 5},#{total_cpu * 5}"
  r.critical_condition = "#{total_cpu * 8 + 10},#{total_cpu * 8 + 5},#{total_cpu * 8}"
end

if node['osl-openstack']['node_type'] == 'controller'
  package 'nagios-plugins-http'

  # Hit this node's API daemons directly: on HA controllers that's the
  # per-host private IP Apache binds to (api_listen_ip); on non-HA
  # single-controller deploys Apache binds wildcard, so node['ipaddress']
  # is the right target.
  local_ip = openstack_local_api_endpoint

  # keystone and novnc are the two backends that terminate TLS
  # themselves on non-HA single-controller (Apache mod_ssl /
  # nova-novncproxy --ssl_only); in HA mode they serve plain HTTP /
  # plain ws on the per-host IP and haproxy on the VIP is the TLS
  # endpoint. The local nrpe check has to match what the backend
  # actually speaks, so drop --ssl when haproxy_tls is on.
  backend_ssl_opt = openstack_tls_on_haproxy? ? '' : '--ssl '

  nrpe_check 'check_keystone_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "#{backend_ssl_opt}-I #{local_ip} -p 5000"
  end

  nrpe_check 'check_glance_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{local_ip} -p 9292"
  end

  nrpe_check 'check_nova_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{local_ip} -p 8774"
  end

  nrpe_check 'check_nova_placement_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{local_ip} -p 8778"
  end

  nrpe_check 'check_novnc' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "#{backend_ssl_opt}-I #{local_ip} -p 6080"
  end

  nrpe_check 'check_neutron_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{local_ip} -p 9696"
  end

  nrpe_check 'check_cinder_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{local_ip} -p 8776"
  end

  nrpe_check 'check_heat_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{local_ip} -p 8004"
  end

  file '/usr/local/etc/os_cluster' do
    content "export OS_CLUSTER=#{s['database_server']['suffix']}\n"
  end

  chef_gem 'prometheus_reporter' do
    version '1.1.1'
    source 'https://packagecloud.io/osuosl/prometheus_reporter'
  end

  cookbook_file '/usr/local/libexec/openstack-prometheus' do
    mode '755'
  end

  cookbook_file '/usr/local/libexec/openstack-prometheus.rb' do
    mode '755'
  end

  cron 'openstack-prometheus' do
    command '/usr/local/libexec/openstack-prometheus'
    minute '*/10'
  end
end

# Shared RabbitMQ messaging tier nodes.
if node['osl-openstack']['node_type'] == 'messaging'
  m = s['messaging']
  listen_port = m['tls'] ? 5671 : 5672

  # check_rabbitmq_cluster parses cluster_status JSON with python3.
  package 'python3'

  # rabbitmq-diagnostics/rabbitmqctl need the Erlang cookie (root).
  node.default['authorization']['sudo']['include_sudoers_d'] = true
  %w(nagios nrpe).each do |u|
    sudo "check_rabbitmq-#{u}" do
      user u
      runas 'root'
      nopasswd true
      commands %w(
        /usr/sbin/rabbitmq-diagnostics
        /usr/sbin/rabbitmqctl
      )
    end
  end

  cookbook_file "#{node['nrpe']['plugin_dir']}/check_rabbitmq_cluster" do
    mode '755'
  end

  nrpe_check 'check_rabbitmq_running' do
    command 'sudo /usr/sbin/rabbitmq-diagnostics'
    parameters '-q check_running'
  end

  nrpe_check 'check_rabbitmq_alarms' do
    command 'sudo /usr/sbin/rabbitmq-diagnostics'
    parameters '-q check_alarms'
  end

  nrpe_check 'check_rabbitmq_cluster' do
    command "#{node['nrpe']['plugin_dir']}/check_rabbitmq_cluster"
    parameters((m['cmr_target_group_size'] || 3).to_s)
  end

  nrpe_check 'check_rabbitmq_listener' do
    command 'sudo /usr/sbin/rabbitmq-diagnostics'
    parameters "-q check_port_listener #{listen_port}"
  end
end
