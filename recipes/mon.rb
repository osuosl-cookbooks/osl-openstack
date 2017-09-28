#
# Cookbook Name:: osl-openstack
# Recipe:: mon
#
# Copyright (C) 2014-2016 Oregon State University
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

# Increase load threshold on openpower nodes (double the default values)
if node['kernel']['machine'] == 'ppc64le'
  total_cpu = node['cpu']['total']
  r = resources(nrpe_check: 'check_load')
  r.warning_condition = "#{total_cpu * 5 + 10},#{total_cpu * 5 + 5},#{total_cpu * 5}"
  r.critical_condition = "#{total_cpu * 8 + 10},#{total_cpu * 8 + 5},#{total_cpu * 8}"
end

include_recipe 'osl-nrpe'
if node['osl-openstack']['node_type'] == 'controller'
  include_recipe 'osl-openstack'
  include_recipe 'base::oslrepo'
  include_recipe 'git'

  # Remove old openstack nagios plugins and their checks
  package 'nagios-plugins-openstack' do
    action :remove
  end

  %w(
    check_nova_services
    check_nova_hypervisors
    check_nova_images
    check_neutron_agents
    check_cinder_services
  ).each do |check|
    nrpe_check check do
      action :remove
    end
  end

  check_openstack = ::File.join(node['nrpe']['plugin_dir'], 'check_openstack')
  tools_dir = ::File.join(Chef::Config[:file_cache_path], 'osops-tools-monitoring')

  python_execute 'monitoring-for-openstack deps' do
    virtualenv '/opt/osc'
    command '-m pip install -r requirements.txt'
    cwd ::File.join(tools_dir, 'monitoring-for-openstack')
    action :nothing
  end

  python_execute 'monitoring-for-openstack install' do
    virtualenv '/opt/osc'
    command 'setup.py install'
    cwd ::File.join(tools_dir, 'monitoring-for-openstack')
    action :nothing
  end

  git tools_dir do
    revision '62160d10683023c8c9d96f616223d8def88b870d'
    repository 'https://git.openstack.org/openstack/osops-tools-monitoring'
    notifies :run, 'python_execute[monitoring-for-openstack deps]', :immediately
    notifies :run, 'python_execute[monitoring-for-openstack install]', :immediately
  end

  # Wrapper for using sudo to check openstack services
  file check_openstack do
    mode 0755
    content <<-EOF
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
    check_cinder_api
    check_glance_api
    check_keystone_api
    check_neutron_api
    check_neutron_floating_ip
  ).each do |check|
    link "#{node['nrpe']['plugin_dir']}/#{check}" do
      to "/usr/libexec/openstack-monitoring/checks/oschecks-#{check}"
    end

    nrpe_check check do
      command "/bin/sudo #{check_openstack} #{check}"
    end
  end

  link "#{node['nrpe']['plugin_dir']}/check_nova_api" do
    to '/usr/libexec/openstack-monitoring/checks/oschecks-check_nova_api'
  end

  nrpe_check 'check_nova_api' do
    command "/bin/sudo #{check_openstack} check_nova_api"
    parameters '--os-compute-api-version 2'
  end
end
