#
# Cookbook Name:: osl-openstack
# Recipe:: default
#
# Copyright (C) 2014 Oregon State University
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
case node['platform']
when 'fedora'
  node.default['openstack']['yum']['uri'] = "http://repos.fedorapeople.org/repos/openstack/openstack-#{node['openstack']['release']}/fedora-20"
  node.default['openstack']['yum']['repo-key'] = "https://github.com/redhat-openstack/rdo-release/raw/#{node['openstack']['release']}/RPM-GPG-KEY-RDO-#{node['openstack']['release'].capitalize}"
when 'centos'
  node.default['openstack']['yum']['uri'] = "http://repos.fedorapeople.org/repos/openstack/openstack-#{node['openstack']['release']}/epel-6"
  node.default['openstack']['yum']['repo-key'] = "https://github.com/redhat-openstack/rdo-release/raw/#{node['openstack']['release']}/RPM-GPG-KEY-RDO-#{node['openstack']['release'].capitalize}"
end

# Set database attributes with our suffix setting
database_suffix = node['osl-openstack']['database_suffix']
if database_suffix
  node['osl-openstack']['databases'].each_pair do |db,name|
    node.default['openstack']['db'][db]['db_name'] = "#{name}_#{database_suffix}"
    node.default['openstack']['db'][db]['username'] = "#{name}_#{database_suffix}"
  end
end

# set data bag attributes with our prefix
databag_prefix = node['osl-openstack']['databag_prefix']
if databag_prefix
  node['osl-openstack']['data_bags'].each do |d|
    node.default['openstack']['secret']["#{d}_data_bag"] = "#{databag_prefix}_#{d}"
  end
end
