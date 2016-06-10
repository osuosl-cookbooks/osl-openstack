#
# Cookbook Name:: osl-openstack
# Recipe:: compute
#
# Copyright (C) 2014, 2015 Oregon State University
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
include_recipe 'firewall'
include_recipe 'firewall::openstack'
include_recipe 'firewall::vnc'
include_recipe 'osl-openstack::default'

modules 'tun'

case node['kernel']['machine']
when 'ppc64', 'ppc64le'
  include_recipe 'chef-sugar::default'
  if %w(openstack).include?(node.deep_fetch('cloud', 'provider'))
    modules 'kvm_pr'
  else
    modules 'kvm_hv'
  end

  # Turn off smt on boot (required for KVM support)
  # NOTE: This really should be handled via an rclocal cookbook
  cookbook_file '/etc/rc.d/rc.local' do
    owner 'root'
    group 'root'
    mode 0755
  end

  # Turn off smt during runtime
  execute 'ppc64_cpu_smt_off' do
    command '/sbin/ppc64_cpu --smt=off'
    not_if '/sbin/ppc64_cpu --smt 2>&1 | ' \
      'grep -E \'SMT is off|Machine is not SMT capable\''
  end
end

# CentOS 7.2 removes provides for nfs-utils-lib so lets set it to libnfsidmap
# which is what CentOS 7 and Fedora uses anyways.
# node.default['openstack']['compute']['platform']['nfs_packages'] = %w(
#   nfs-utils
#   libnfsidmap)

int_mappings = []
node['osl-openstack']['physical_interface_mappings'].each do |int|
  int_mappings.push("#{int['name']}:#{int['compute']}")
end

node.default['openstack']['network']['linuxbridge']['physical_interface_mappings'] = \
  int_mappings.join(',')

include_recipe 'openstack-compute::compute'
# include_recipe 'osl-openstack::linuxbridge'
# include_recipe 'openstack-telemetry::agent-compute'
# include_recipe 'openstack-bare-metal::conductor'
