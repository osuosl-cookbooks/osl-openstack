#
# Cookbook Name:: osl-packstack
# Recipe:: default
#
# Copyright 2013, Oregon State University
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



#################################################################################################
# What this recipe accomplishes:  This recipe will enable to RDO repos to be able to setup      #
#                                 openstack using RDO Foreman.                                  #
#                                                                                               #
# What this recipe does:          This recipe is given a remote URL to the rpm that will        #
#                                 enable all the required repos for openstack installation      #
#                                 using RDO Foreman.                                            #
#################################################################################################
remote_file "#{Chef::Config[:file_cache_path]}/rdo-release.rpm" do
  source node['rdo_repo_url']
  action :create
end

rpm_package "rdo-release" do
  source "#{Chef::Config[:file_cache_path]}/rdo-release.rpm"
  action :install
end
