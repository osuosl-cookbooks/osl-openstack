#
# Cookbook:: osl-openstack
# Recipe:: mon
#
# Copyright:: 2014-2022, Oregon State University
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
  include_recipe 'osl-openstack'
  include_recipe 'osl-repos::oslrepo'
  include_recipe 'git'
  include_recipe 'base::python'

  venv = '/opt/osc-nagios'

  execute "virtualenv -p python3 #{venv}" do
    creates "#{venv}/bin/pip"
  end

  # Remove old openstack nagios plugins and their checks
  package 'nagios-plugins-openstack' do
    action :remove
  end

  %w(
    check_cinder_api
    check_cinder_services
    check_neutron_agents
    check_neutron_floating_ip
    check_nova_hypervisors
    check_nova_images
    check_nova_services
  ).each do |check|
    nrpe_check check do
      action :remove
    end
  end

  check_openstack = ::File.join(node['nrpe']['plugin_dir'], 'check_openstack')
  tools_dir = ::File.join(Chef::Config[:file_cache_path], 'osops', 'tools', 'monitoring')

  execute 'monitoring-for-openstack deps' do
    command "#{venv}/bin/pip install -c constraints.txt -r requirements.txt"
    cwd ::File.join(tools_dir, 'monitoring-for-openstack')
    action :nothing
  end

  execute 'monitoring-for-openstack install' do
    command "#{venv}/bin/python setup.py install"
    cwd ::File.join(tools_dir, 'monitoring-for-openstack')
    action :nothing
  end

  git ::File.join(Chef::Config[:file_cache_path], 'osops') do
    revision node['openstack']['release']
    repository 'https://github.com/osuosl/osops.git'
    notifies :run, 'execute[monitoring-for-openstack deps]', :immediately
    notifies :run, 'execute[monitoring-for-openstack install]', :immediately
  end

  # Wrapper for using sudo to check openstack services
  file check_openstack do
    mode '755'
    content <<~EOF
      #!/bin/bash

      source /root/openrc
      #{node['nrpe']['plugin_dir']}/${@}
    EOF
  end

  sudo 'nrpe-openstack' do
    user '%nrpe'
    nopasswd true
    runas 'root'
    commands [check_openstack]
  end

  %w(
    check_glance_api
    check_keystone_api
    check_neutron_api
  ).each do |check|
    osc_nagios_check check
  end

  osc_nagios_check 'check_nova_api' do
    parameters '--os-compute-api-version 2'
  end

  osc_nagios_check 'check_cinder_api_v2' do
    plugin 'check_cinder_api'
    parameters '--os-volume-api-version 2'
  end

  osc_nagios_check 'check_cinder_api_v3' do
    plugin 'check_cinder_api'
    parameters '--os-volume-api-version 3'
  end

  node['osl-openstack']['external_networks'].each do |network|
    osc_nagios_check "check_neutron_floating_ip_#{network}" do
      plugin 'check_neutron_floating_ip'
      parameters "--ext_network_name #{network}"
    end
  end

  unless node['osl-openstack']['cluster_name'].nil?
    file '/usr/local/etc/os_cluster' do
      content "export OS_CLUSTER=#{node['osl-openstack']['cluster_name']}\n"
    end

    chef_gem 'prometheus_reporter' do
      # TODO: https://github.com/nattfodd/prometheus_reporter/pull/5
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
end
