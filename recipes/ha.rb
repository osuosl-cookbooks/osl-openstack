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

# Honor haproxy's X-Forwarded-* headers; set before anything includes
# osl-apache, which is why controller.rb includes ha first.
node.default['osl-apache']['behind_loadbalancer'] = true

# Allow HAProxy on the standby controller to bind to the VIP it doesn't
# currently hold; on failover the bind takes effect immediately.
%w(net.ipv4.ip_nonlocal_bind net.ipv6.ip_nonlocal_bind).each do |key|
  sysctl key do
    value 1
  end
end

{ 'openstack-ipv4' => k['vip_v4'], 'openstack-ipv6' => k['vip_v6'] }.compact.each do |instance, vip|
  keepalived_vrrp_instance instance do
    master k['primary'][node['fqdn']]
    interface k['interface'][node['fqdn']]
    virtual_router_id k['virtual_router_id']
    priority k['priority'][node['fqdn']]
    authentication auth_type: 'PASS', auth_pass: k['auth_pass']
    virtual_ipaddress [vip]
    notifies :reload, 'service[keepalived]'
  end
end

keepalived_vrrp_sync_group 'openstack' do
  group %w(openstack-ipv4 openstack-ipv6)
  notifies :reload, 'service[keepalived]'
end if k['vip_v6']

service 'keepalived' do
  action [:enable, :start]
end

# HAProxy fronts the APIs on the VIP while Apache binds per-host IPs; the EL9
# package preset leaves haproxy stopped until our config has rendered.
include_recipe 'osl-haproxy::install'

# haproxy terminates TLS on the VIP and wants one combined cert+chain+key
# PEM directly under /etc/haproxy/certs; :reload keeps in-flight sessions.
directory '/etc/haproxy/certs' do
  owner 'haproxy'
  group 'haproxy'
  mode '0700'
end

certificate_manage 'wildcard-haproxy' do
  search_id 'wildcard'
  cert_path '/etc/haproxy/certs'
  cert_file 'wildcard.pem'
  key_file 'wildcard.key'
  chain_file 'wildcard-bundle.crt'
  owner 'haproxy'
  group 'haproxy'
  combined_file true
  create_subfolders false
  # service[haproxy] lives in the root run context, so notify the wrapper
  notifies :reload, 'haproxy_service[haproxy]'
end

haproxy_config_global 'global' do
  user 'haproxy'
  group 'haproxy'
  maxconn 4096
  log '/dev/log local0 info'
  # Same TLS floor Apache had with `SSLProtocol -all +TLSv1.2`
  tuning(
    'ssl.default-dh-param' => 2048
  )
  extra_options(
    'ssl-default-bind-options' => 'no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets'
  )
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

# keepalived takes the VIP in CIDR form but haproxy bind rejects it, so
# strip any prefix length here.
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

# Per-source rate limit on every VIP listener after the 2026-08-14 scanner;
# tune ha.haproxy.throttle {conn_rate, exempt} in the data bag.
throttle = stats['throttle'] || {}
throttle_rate = throttle['conn_rate'] || 50
throttle_exempt = throttle['exempt'] || %w(10.0.0.0/8 127.0.0.0/8 140.211.0.0/16)
throttle_opts = {
  # type ipv6 holds both families (v4 arrives IPv4-mapped).
  'stick-table' => 'type ipv6 size 100k expire 10m store conn_rate(10s)',
  'tcp-request' => [
    'connection track-sc0 src if !throttle_exempt',
    "connection reject if { sc0_conn_rate gt #{throttle_rate} }",
  ],
}

# tls services terminate at haproxy in mode http; the rest stay mode tcp.
# The second haproxy_listen per service only adds the IPv6 bind.
openstack_ha_services.each do |svc|
  port = svc[:port]
  servers = controllers.map { |fqdn| "#{fqdn} #{listen_ips[fqdn]}:#{port} check" }
  cert_opt = svc[:tls] ? ' ssl crt /etc/haproxy/certs/wildcard.pem' : ''

  haproxy_listen svc[:name] do
    bind "#{vip4}:#{port}#{cert_opt}"
    acl ["throttle_exempt src #{throttle_exempt.join(' ')}"]
    if svc[:redirect_to_https]
      # Redirect-only listener; Apache's :80 rewrite would loop behind
      # haproxy, so the 301 lives here with no backend servers.
      mode 'http'
      http_request ['redirect scheme https code 301']
      extra_options(throttle_opts)
    else
      mode svc[:tls] ? 'http' : 'tcp'
      option ['forwardfor'] if svc[:tls]
      # Lets Django and oslo build https redirects and secure cookies
      http_request [
        'set-header X-Forwarded-Proto https if { ssl_fc }',
        'set-header X-Forwarded-Proto http if !{ ssl_fc }',
      ] if svc[:tls]
      extra_options(throttle_opts.merge('balance' => svc[:balance] || 'roundrobin'))
      server servers
    end
  end

  haproxy_listen svc[:name] do
    bind "[#{vip6}]:#{port}#{cert_opt}"
  end if vip6
end

# Trust every controller's listen IP for mod_remoteip; identity.rb includes
# the recipe after overriding the listen address.
node.default['osl-apache']['mod_remoteip']['trusted_proxy'] =
  (node['osl-apache']['mod_remoteip']['trusted_proxy'] || []) +
  listen_ips.values +
  %w(127.0.0.1 ::1)

haproxy_service 'haproxy' do
  action [:enable, :start]
end

# Start haproxy mid-run on first bootstrap: later recipes call keystone
# through the VIP, and the cookbook's own start is delayed to end of run.
service 'haproxy_eager_start' do
  service_name 'haproxy'
  supports status: true
  action :nothing
end

ruby_block 'render haproxy.cfg + start haproxy before api calls' do
  block do
    run_context.resource_collection
               .find('template[/etc/haproxy/haproxy.cfg]')
               .run_action(:create)
  end
  notifies :enable, 'service[haproxy_eager_start]', :immediately
  notifies :start, 'service[haproxy_eager_start]', :immediately
  not_if { haproxy_running? }
end

# Restart haproxy after the native API daemons move off their wildcard
# sockets, or the VIP bind fails; unique name avoids service[haproxy].
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
