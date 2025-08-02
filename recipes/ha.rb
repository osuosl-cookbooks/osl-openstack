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
# controllers. Apache on each controller binds to its per-host listen IP
# (see openstack_api_listen_ip), so HAProxy can bind the same ports on
# the VIP without conflict.
#
# Install haproxy first so the package creates /etc/haproxy and the
# haproxy user; then overwrite the package-default haproxy.cfg with a
# minimal stub before the delayed service[haproxy] :start fires. The
# package config has `bind *:5000` for a demo frontend, which would
# hold a wildcard socket that prevents Apache from binding the per-host
# IP on the same port even after our config replaces it (graceful
# reload preserves listening sockets in stuck old workers).
include_recipe 'osl-haproxy::install'

# If haproxy is already running (the package was just installed with
# the demo frontend, or carrying over from a prior chef run), restart
# it right after we overwrite haproxy.cfg with the stub. Otherwise the
# old wildcard sockets stay bound in memory and Apache/daemons can't
# bind their per-host IPs.
execute 'haproxy_release_wildcards' do
  command 'systemctl is-active haproxy >/dev/null 2>&1 && systemctl restart haproxy || true'
  action :nothing
end

file '/etc/haproxy/haproxy.cfg' do
  # haproxy 3.x rejects configs with no proxies, and `service[haproxy]
  # :start` (queued by haproxy_service[haproxy] in osl-haproxy::install)
  # fires before the real haproxy.cfg template's delayed_action :create
  # renders. The dummy localhost listen makes this stub valid so the
  # initial start succeeds; the proper template renders later in the
  # delayed phase and reloads haproxy with the real listeners.
  content <<~EOC
    global
        daemon
    defaults
        mode tcp
        timeout connect 10s
        timeout client 1m
        timeout server 1m
    listen _placeholder
        bind 127.0.0.1:18999
  EOC
  mode '0644'
  # Write the stub when the file is missing OR still holds the
  # package-default sample frontend (which has "bind *:5000"). Skip
  # if our Chef-managed config (which never uses bind *:) is already
  # in place - we don't want to wipe live listeners on every run.
  only_if do
    !::File.exist?('/etc/haproxy/haproxy.cfg') ||
      ::File.read('/etc/haproxy/haproxy.cfg').match?(/^\s*bind\s+\*:/)
  end
  notifies :run, 'execute[haproxy_release_wildcards]', :immediately
end

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

vip4 = k['vip_v4']
vip6 = k['vip_v6']
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
