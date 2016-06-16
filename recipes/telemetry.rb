#
# Cookbook Name:: osl-openstack
# Recipe:: telemetry
#
# Copyright (C) 2016 Oregon State University
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
include_recipe 'osl-openstack'
include_recipe 'openstack-telemetry::api'
include_recipe 'openstack-telemetry::agent-central'
include_recipe 'openstack-telemetry::agent-notification'
include_recipe 'openstack-telemetry::collector'
include_recipe 'openstack-telemetry::identity_registration'
