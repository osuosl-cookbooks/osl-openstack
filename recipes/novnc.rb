#
# Cookbook Name:: osl-openstack
# Recipe:: novnc
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
node.default['openstack']['novnc']['ssl']['use_ssl'] = true

# Location of ssl cert and key to use
node.default['openstack']['novnc']['ssl']['dir'] = '/etc/ssl/nova'

# Name of ssl certificate for nova-novncproxy to use
node.default['openstack']['novnc']['ssl']['cert'] = 'nova.pem'
node.default['openstack']['novnc']['ssl']['key']  = 'nova.key'

# Remote uri for the certificate and key
# This assumes the certificate::wildcard recipe was run beforehand
node.default['openstack']['novnc']['ssl']['cert_url'] = nil
node.default['openstack']['novnc']['ssl']['key_url'] = nil

if node['openstack']['novnc']['ssl']['use_ssl']
  directory node['openstack']['novnc']['ssl']['dir'] do
    owner 'root'
    group 'nova'
    mode 00755
    action :create
  end

  cert_file = node['openstack']['novnc']['ssl']['dir'] + \
              '/' + node['openstack']['novnc']['ssl']['cert']
  cert_mode = 00644
  cert_owner = 'root'
  cert_group = 'nova'
  if node['openstack']['novnc']['ssl']['cert_url']
    remote_file cert_file do
      source node['openstack']['novnc']['ssl']['cert_url']
      mode cert_mode
      owner cert_owner
      group cert_group
      notifies :restart, 'service[openstack-nova-novncproxy]'
    end
  else
    cookbook_file cert_file do
      source 'novnc.pem'
      mode cert_mode
      owner cert_owner
      group cert_group
      notifies :restart, 'service[openstack-nova-novncproxy]'
    end
  end

  key_file = node['openstack']['novnc']['ssl']['dir'] + \
             '/' + node['openstack']['novnc']['ssl']['key']
  key_mode = 00644
  key_owner = 'root'
  key_group = 'nova'
  if node['openstack']['novnc']['ssl']['key_url']
    remote_file key_file do
      source node['openstack']['novnc']['ssl']['key_url']
      mode key_mode
      owner key_owner
      group key_group
      notifies :restart, 'service[openstack-nova-novncproxy]'
    end
  else
    cookbook_file key_file do
      source 'novnc.key'
      mode key_mode
      owner key_owner
      group key_group
      notifies :restart, 'service[openstack-nova-novncproxy]'
    end
  end
else
  cert_file = nil
  key_file = nil
end

template '/etc/sysconfig/openstack-nova-novncproxy' do
  source 'novncproxy.erb'
  mode 00644
  owner 'root'
  group 'root'
  variables(cert: cert_file,
            key: key_file,
            host: node['fqdn'])
  notifies :restart, 'service[openstack-nova-novncproxy]'
end
