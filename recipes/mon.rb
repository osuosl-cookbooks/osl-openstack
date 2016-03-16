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
