#
# Cookbook Name:: osl-openstack
# Recipe:: default
#
# Copyright (C) 2014-2015 Oregon State University
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
node.default['authorization']['sudo']['include_sudoers_d'] = true
node.default['apache']['contact'] = 'hostmaster@osuosl.org'
node.default['openstack']['compute']['config']['allow_same_net_traffic'] =
  false
node.default['openstack']['compute']['config']['ram_allocation_ratio'] = '5.0'
node.default['openstack']['compute']['network']['service_type'] = 'nova'
node.default['openstack']['compute']['network']['multi_host'] = true
node.default['openstack']['compute']['network']['force_dhcp_release'] = true
node.default['openstack']['libvirt']['virt_type'] = 'kvm'
node.default['openstack']['dashboard']['keystone_default_role'] = '_member_'
node.default['openstack']['dashboard']['ssl']['cert'] = 'horizon.pem'
node.default['openstack']['dashboard']['ssl']['cert_url'] =
  'file:///etc/pki/tls/certs/wildcard.pem'
node.default['openstack']['dashboard']['ssl']['chain'] = 'wildcard-bundle.crt'
node.default['openstack']['dashboard']['ssl']['key'] = 'horizon.key'
node.default['openstack']['dashboard']['ssl']['key_url'] =
  'file:///etc/pki/tls/private/wildcard.key'
node.default['openstack']['endpoints']['compute-novnc']['scheme'] = 'https'
node.default['openstack']['developer_mode'] = false
node.default['openstack']['release'] = 'icehouse'
node.default['openstack']['secret']['key_path'] =
  '/etc/chef/encrypted_data_bag_secret'
node.default['openstack']['sysctl']['net.ipv4.conf.all.rp_filter'] = 0
node.default['openstack']['sysctl']['net.ipv4.conf.default.rp_filter'] = 0
node.default['openstack']['sysctl']['net.ipv4.ip_forward'] = 1

case node['platform']
when 'fedora'
  node.default['openstack']['yum']['uri'] = 'http://repos.fedorapeople.org/' \
    "repos/openstack/EOL/openstack-#{node['openstack']['release']}/fedora-20"
  node.default['openstack']['yum']['repo-key'] = 'https://github.com/' \
    "redhat-openstack/rdo-release/raw/#{node['openstack']['release']}/" \
    "RPM-GPG-KEY-RDO-#{node['openstack']['release'].capitalize}"
  node.default['openstack']['compute']['platform']['dbus_service'] = 'dbus'
  node.default['openstack']['db']['python_packages']['mysql'] =
    %w(MySQL-python)
  case node['kernel']['machine']
  when 'ppc64'
    node.default['modules']['modules'] = %w(kvm_hv)
    node.default['yum']['fedora']['exclude'] = 'kernel* libvirt qemu* ksm ' \
      'libcacard* perf* python-perf*'
    node.default['yum']['updates']['exclude'] = 'kernel* libvirt qemu* ksm ' \
      'libcacard* perf* python-perf*'
  end
when 'centos'
  node.default['openstack']['yum']['uri'] = 'http://repos.fedorapeople.org/' \
    "repos/openstack/EOL/openstack-#{node['openstack']['release']}/epel-6"
  node.default['openstack']['yum']['repo-key'] = 'https://github.com/' \
    "redhat-openstack/rdo-release/raw/#{node['openstack']['release']}/" \
    "RPM-GPG-KEY-RDO-#{node['openstack']['release'].capitalize}"
end

# Set database attributes with our suffix setting
database_suffix = node['osl-openstack']['database_suffix']
if database_suffix
  node['osl-openstack']['databases'].each_pair do |db, name|
    node.default['openstack']['db'][db]['db_name'] =
      "#{name}_#{database_suffix}"
    node.default['openstack']['db'][db]['username'] =
      "#{name}_#{database_suffix}"
  end
end

# set data bag attributes with our prefix
databag_prefix = node['osl-openstack']['databag_prefix']
if databag_prefix
  node['osl-openstack']['data_bags'].each do |d|
    node.default['openstack']['secret']["#{d}_data_bag"] =
      "#{databag_prefix}_#{d}"
  end
end

include_recipe 'base::ifconfig'
include_recipe 'selinux::permissive'
include_recipe 'openstack-common'
include_recipe 'openstack-common::logging'
include_recipe 'openstack-common::set_endpoints_by_interface'
include_recipe 'openstack-common::sysctl'
include_recipe 'openstack-common::openrc'
