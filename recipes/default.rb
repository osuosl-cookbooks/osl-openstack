#
# Cookbook Name:: osl-packstack
# Recipe:: default
#
# Copyright 2013, Geoffrey Corey
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Setup the epel repo
case node['platform']
when "centos"
  include_recipe "yum::epel"
end

# Using these vars enhances readability
pltfrm_vers = node['platform_version'].to_i
release_ver = node['osl-packstack']['rdo']['release'].downcase # Sanity check, and I'd like to start from an ensured lowercase

# Setup the rdo repo
yum_repository "openstack" do
  repo_name "openstack-#{release_ver}"
  description "Openstack #{release_ver.capitalize} repo." # Make first letter capital
  url "http://repos.fedorapeople.org/repos/openstack/openstack-#{release_ver}/epel-#{platfrm_ver}/"
  key "RPM-GPG-KEY-RDO-#{release_ver.upcase}" # Make entirely uppercase
  action :add
end

# Install packstack
package "openstack-packstack" do
  action :install
end
