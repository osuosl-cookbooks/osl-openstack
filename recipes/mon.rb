#
# Cookbook:: osl-openstack
# Recipe:: mon
#
# Copyright:: 2014-2023, Oregon State University
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

# Increase load threshold on openpower nodes (double the default values)
if node['kernel']['machine'] == 'ppc64le'
  total_cpu = node['cpu']['total']
  r = resources(nrpe_check: 'check_load')
  r.warning_condition = "#{total_cpu * 5 + 10},#{total_cpu * 5 + 5},#{total_cpu * 5}"
  r.critical_condition = "#{total_cpu * 8 + 10},#{total_cpu * 8 + 5},#{total_cpu * 8}"
end

if node['osl-openstack']['node_type'] == 'controller'
  package 'nagios-plugins-http'

  nrpe_check 'check_keystone_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "--ssl -I #{node['osl-openstack']['bind_service']} -p 5000"
  end

  nrpe_check 'check_glance_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{node['osl-openstack']['bind_service']} -p 9292"
  end

  nrpe_check 'check_nova_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{node['osl-openstack']['bind_service']} -p 8774"
  end

  nrpe_check 'check_nova_placement_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{node['osl-openstack']['bind_service']} -p 8778"
  end

  nrpe_check 'check_novnc' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "--ssl -I #{node['osl-openstack']['bind_service']} -p 6080"
  end

  nrpe_check 'check_neutron_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{node['osl-openstack']['bind_service']} -p 9696"
  end

  nrpe_check 'check_cinder_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{node['osl-openstack']['bind_service']} -p 8776"
  end

  nrpe_check 'check_heat_api' do
    command "#{node['nrpe']['plugin_dir']}/check_http"
    parameters "-I #{node['osl-openstack']['bind_service']} -p 8004"
  end

  unless node['osl-openstack']['cluster_name'].nil?
    file '/usr/local/etc/os_cluster' do
      content "export OS_CLUSTER=#{node['osl-openstack']['cluster_name']}\n"
    end

    chef_gem 'prometheus_reporter'

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
end
