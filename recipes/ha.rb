#
# Cookbook:: osl-openstack
# Recipe:: ha
#
# Copyright:: 2025-2026, Oregon State University
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
include_recipe 'osl-keepalived'

s = os_secrets
h = s['ha']
k = h['keepalived']

# Allow HAProxy on the standby controller to bind to the VIP it doesn't
# currently hold; on failover the bind takes effect immediately.
%w(net.ipv4.ip_nonlocal_bind net.ipv6.ip_nonlocal_bind).each do |key|
  sysctl key do
    value 1
  end
end

keepalived_vrrp_instance 'openstack-ipv4' do
  master k['primary'][node['fqdn']]
  interface k['interface'][node['fqdn']]
  virtual_router_id k['virtual_router_id']
  priority k['priority'][node['fqdn']]
  authentication auth_type: 'PASS', auth_pass: k['auth_pass']
  virtual_ipaddress [k['vip_v4']]
  notifies :reload, 'service[keepalived]'
end

keepalived_vrrp_instance 'openstack-ipv6' do
  master k['primary'][node['fqdn']]
  interface k['interface'][node['fqdn']]
  virtual_router_id k['virtual_router_id']
  priority k['priority'][node['fqdn']]
  authentication auth_type: 'PASS', auth_pass: k['auth_pass']
  virtual_ipaddress [k['vip_v6']]
  notifies :reload, 'service[keepalived]'
end if k['vip_v6']

keepalived_vrrp_sync_group 'openstack' do
  group %w(openstack-ipv4 openstack-ipv6)
  notifies :reload, 'service[keepalived]'
end if k['vip_v6']

service 'keepalived' do
  action [:enable, :start]
end

# HAProxy: front the OpenStack APIs on the VIP, balancing across both
# controllers. Apache on each controller binds to its per-host listen
# IP (see openstack_api_listen_ip), so HAProxy can bind the same ports
# on the VIP without conflict.
#
# On EL9 the haproxy package preset is `disabled`, so the install
# itself doesn't start the daemon — the delayed service[haproxy]
# :start (queued by haproxy_service[haproxy] in osl-haproxy::install)
# is the first thing to run it, and by then the haproxy.cfg template
# declared by haproxy_config_global below has rendered. If you ever
# run this on a platform where the package auto-starts haproxy with
# its demo `bind *:5000` config, stop the daemon out of band before
# applying this recipe so it doesn't squat on a wildcard socket.
include_recipe 'osl-haproxy::install'

haproxy_config_global 'global' do
  user 'haproxy'
  group 'haproxy'
  maxconn 4096
  log '/dev/log local0 info'
end

haproxy_config_defaults 'defaults' do
  log 'global'
  mode 'tcp'
  maxconn 4096
  timeout(
    'connect' => '10s',
    'client' => '1m',
    'server' => '1m'
  )
  option %w(redispatch dontlognull tcplog)
  haproxy_retries 3
end

# keepalived wants the VIP in CIDR form (`192.0.2.10/24`,
# `2001:db8::10/64`) so it adds the route with the right netmask;
# haproxy `bind` rejects CIDR and wants the bare address. Allow the
# data bag to carry either form and strip the suffix for haproxy.
vip4 = k['vip_v4'].to_s.split('/', 2).first
vip6 = k['vip_v6'].to_s.split('/', 2).first if k['vip_v6']
listen_ips = h['api_listen_ip']
controllers = listen_ips.keys.sort

stats = h['haproxy'] || {}
if stats['stats_user'] && stats['stats_pass']
  haproxy_listen 'stats' do
    bind "#{listen_ips[node['fqdn']]}:9000"
    mode 'http'
    stats(
      'enable' => '',
      'uri' => '/',
      'realm' => 'HAProxy stats',
      'auth' => "#{stats['stats_user']}:#{stats['stats_pass']}"
    )
  end
end

# OpenStack APIs fronted by HAProxy. Apache terminates TLS on each
# backend; HAProxy operates in TCP mode so certificates stay in one place.
# Horizon uses balance source for session affinity to its memcached store.
# HAProxy needs one bind directive per address family, so we declare the
# resource twice per service: first call sets all properties, second call
# adds only the IPv6 bind.
openstack_ha_services.each do |svc|
  port = svc[:port]
  servers = controllers.map { |fqdn| "#{fqdn} #{listen_ips[fqdn]}:#{port} check" }

  haproxy_listen svc[:name] do
    bind "#{vip4}:#{port}"
    mode 'tcp'
    extra_options('balance' => svc[:balance] || 'roundrobin')
    server servers
  end

  haproxy_listen svc[:name] do
    bind "[#{vip6}]:#{port}"
  end if vip6
end

haproxy_service 'haproxy' do
  action [:enable, :start]
end

# The haproxy.cfg template subscribed by osl-haproxy::install fires a
# :reload at end of run, but it's registered early (when the first
# haproxy_listen runs) so it fires BEFORE the native API daemons
# (glance-api, neutron-server, heat-api, heat-cfn, nova-novncproxy)
# restart and rebind from 0.0.0.0:port to the per-host listen IP.
# Without this, haproxy tries to bind the VIP port while the daemon
# still holds the wildcard, and fails to start. Subscribing a delayed
# restart of haproxy to those daemons ensures haproxy comes up AFTER
# they've released their wildcard sockets.
#
# We use service_name + a unique resource name (instead of just
# 'haproxy') so we don't collide with the inner service[haproxy] the
# haproxy cookbook declares from haproxy_service[haproxy].
service 'haproxy_post_daemons_restart' do
  service_name 'haproxy'
  action :nothing
  %w(
    openstack-glance-api
    neutron-server
    openstack-heat-api
    openstack-heat-api-cfn
    openstack-nova-novncproxy
  ).each do |svc|
    subscribes :restart, "service[#{svc}]", :delayed
  end
end

osl_firewall_port 'haproxy_stats' do
  ports [9000]
  osl_only true
end
