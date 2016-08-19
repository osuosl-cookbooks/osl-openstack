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
if %w(ppc64 ppc64le).include?(node['kernel']['machine'])
  total_cpu = node['cpu']['total']
  node.default['osl-nrpe']['check_load'] = {
    'warning' => "#{total_cpu * 4 + 10},#{total_cpu * 4 + 5},#{total_cpu * 4}",
    'critical' => "#{total_cpu * 8 + 10},#{total_cpu * 8 + 5},#{total_cpu * 8}"
  }
end

include_recipe 'osl-nrpe'
if node['osl-openstack']['node_type'] == 'controller'
  include_recipe 'osl-openstack'
  include_recipe 'base::oslrepo'
  package 'nagios-plugins-openstack'
  check_openstack = ::File.join(node['nrpe']['plugin_dir'], 'check_openstack')
  mon = node['osl-openstack']['mon']

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

  nrpe_check 'check_nova_services' do
    command '/bin/sudo ' + check_openstack + ' check_nova-services'
    warning_condition mon['check_nova_services']['warning']
    critical_condition mon['check_nova_services']['critical']
  end

  nrpe_check 'check_nova_hypervisors' do
    command '/bin/sudo ' + check_openstack + ' check_nova-hypervisors'
    parameters '--warn_memory_percent ' +
               mon['check_nova_hypervisors']['warn_memory_percent'] +
               ' --critical_memory_percent ' +
               mon['check_nova_hypervisors']['critical_memory_percent'] +
               ' --warn_vcpus_percent ' +
               mon['check_nova_hypervisors']['warn_vcpus_percent'] +
               ' --critical_vcpus_percent ' +
               mon['check_nova_hypervisors']['critical_vcpus_percent']
  end

  nrpe_check 'check_nova_images' do
    command '/bin/sudo ' + check_openstack + ' check_nova-images'
    warning_condition mon['check_nova_images']['warning']
    critical_condition mon['check_nova_images']['critical']
  end

  nrpe_check 'check_neutron_agents' do
    command '/bin/sudo ' + check_openstack + ' check_neutron-agents'
    warning_condition mon['check_neutron_agents']['warning']
    critical_condition mon['check_neutron_agents']['critical']
  end

  nrpe_check 'check_cinder_services' do
    command '/bin/sudo ' + check_openstack + ' check_cinder-services'
    warning_condition mon['check_cinder_services']['warning']
    critical_condition mon['check_cinder_services']['critical']
  end

  nrpe_check 'check_keystone_token' do
    command '/bin/sudo ' + check_openstack + ' check_keystone-token'
  end
end
