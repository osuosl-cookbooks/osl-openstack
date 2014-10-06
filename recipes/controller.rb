#
# Cookbook Name:: osl-openstack
# Recipe:: controller
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
include_recipe "apache2::mod_proxy"
include_recipe "apache2::mod_proxy_http"
include_recipe "apache2::mod_headers"
include_recipe "osl-apache::default"
include_recipe "firewall::openstack"
include_recipe "firewall::amqp"
include_recipe "firewall::vnc"
include_recipe "osl-openstack::_fedora"
include_recipe "osl-openstack::novnc"

# Setup https endpoints for API layer via apache
dashboard = node['openstack']['dashboard']
endpoints = node['openstack']['endpoints']

apache_app "openstack-https-proxy" do
  name dashboard['server_hostname'] if dashboard['server_hostname']
  cert_file "/etc/pki/tls/certs/#{dashboard['ssl']['cert']}"
  cert_key "/etc/pki/tls/private/#{dashboard['ssl']['key']}"
  cert_chain "/etc/pki/tls/certs/#{dashboard['ssl']['chain']}" if dashboard['ssl']['chain']
  ip_address endpoints['host'] == "127.0.0.1" ? node['ipaddress'] : endpoints['host']
  template "https-proxy.conf.erb"
  cookbook "osl-openstack"
  port [ endpoints['identity-api']['port'], endpoints['identity-admin']['port'] ]
end
