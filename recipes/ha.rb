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

# Apache sits behind HAProxy on the VIP, so every request arrives
# from haproxy's source IP. Tell osl-apache to honor X-Forwarded-For
# / X-Forwarded-Proto from haproxy so REMOTE_ADDR + the WSGI/PHP
# scheme reflect the real client instead of the load balancer.
# Set this before any recipe pulls in osl-apache - controller.rb
# includes ha first, so identity/dashboard/etc see this attribute.
node.default['osl-apache']['behind_loadbalancer'] = true

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

# TLS termination moves from Apache / nova-novncproxy to haproxy on
# the VIP. certificate_manage with `combined_file true` writes the
# single cert+chain+key PEM that haproxy's `ssl crt` directive wants;
# `create_subfolders false` keeps the file at /etc/haproxy/certs/
# instead of the default /etc/haproxy/certs/certs/ layout.
# `:reload` is graceful - in-flight connections finish on the old
# cert, new connections get the new cert.
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
  # Notify the wrapper resource, not service[haproxy] - the inner
  # service is declared by the haproxy cookbook inside
  # with_run_context :root and isn't visible to notify-by-name from
  # this recipe.
  notifies :reload, 'haproxy_service[haproxy]'
end

haproxy_config_global 'global' do
  user 'haproxy'
  group 'haproxy'
  maxconn 4096
  log '/dev/log local0 info'
  # Disable old TLS versions and weak options on haproxy's TLS
  # listeners. Matches the policy Apache had via
  # `SSLProtocol -all +TLSv1.2`.
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

# OpenStack APIs fronted by HAProxy.
#
# `tls: true` services (keystone, novnc, horizon-https) terminate TLS
# *at haproxy* on the VIP - mode http, `ssl crt ...` on the bind, and
# `option forwardfor` so the backend sees the real client IP via
# X-Forwarded-For. The backend (Apache vhost or nova-novncproxy)
# serves plain HTTP / ws on its per-host listen IP.
#
# Plain-HTTP services keep mode tcp - the backend native daemons
# (glance / nova / neutron / cinder / heat / placement) don't speak
# proxy-protocol and don't terminate TLS today either; haproxy just
# shuffles bytes. When those endpoints move to HTTPS they flip to
# the same `tls: true` path.
#
# Horizon uses `balance source` for session affinity.
#
# HAProxy needs one bind directive per address family, so we declare
# the resource twice per service: first call sets all properties,
# second call adds only the IPv6 bind.
openstack_ha_services.each do |svc|
  port = svc[:port]
  servers = controllers.map { |fqdn| "#{fqdn} #{listen_ips[fqdn]}:#{port} check" }
  cert_opt = svc[:tls] ? ' ssl crt /etc/haproxy/certs/wildcard.pem' : ''

  haproxy_listen svc[:name] do
    bind "#{vip4}:#{port}#{cert_opt}"
    if svc[:redirect_to_https]
      # Plain-HTTP listener whose only job is to 301 to https. Apache
      # used to do this in its wsgi-horizon :80 vhost; that rewrite is
      # gated off in HA mode (Apache backends serve plain HTTP behind
      # haproxy and would loop on %{HTTPS}=off), so haproxy owns it.
      # No backend servers - every request terminates here.
      mode 'http'
      http_request ['redirect scheme https code 301']
    else
      mode svc[:tls] ? 'http' : 'tcp'
      option ['forwardfor'] if svc[:tls]
      # Tell the backend the request was originally HTTPS so Django /
      # oslo middleware build correct redirect URLs and set the
      # secure-cookie flag. `ssl_fc` is true on the TLS-terminated
      # frontend connection.
      http_request [
        'set-header X-Forwarded-Proto https if { ssl_fc }',
        'set-header X-Forwarded-Proto http if !{ ssl_fc }',
      ] if svc[:tls]
      extra_options('balance' => svc[:balance] || 'roundrobin')
      server servers
    end
  end

  haproxy_listen svc[:name] do
    bind "[#{vip6}]:#{port}#{cert_opt}"
  end if vip6
end

# mod_remoteip: rewrite Apache REMOTE_ADDR from haproxy's
# X-Forwarded-For so logs / WSGI apps see the real client IP. Trust
# every HA controller's api_listen_ip - haproxy connects from there
# when balancing to a backend on the same or sibling controller. The
# default trusted_proxy list in osl-apache is preserved.
#
# Only the attribute is set here; the recipe itself is included from
# identity.rb (after node['osl-apache']['listen'] is overridden), so
# osl-apache::default captures the per-host listen value rather than
# the package default and Apache doesn't bind both *:80 and
# api_listen_ip:80.
node.default['osl-apache']['mod_remoteip']['trusted_proxy'] =
  (node['osl-apache']['mod_remoteip']['trusted_proxy'] || []) +
  listen_ips.values +
  %w(127.0.0.1 ::1)

haproxy_service 'haproxy' do
  action [:enable, :start]
end

# Bring haproxy up during THIS converge instead of at end-of-run.
# osl-haproxy::install and the haproxy_service above only queue a
# *delayed* service[haproxy] :start (and the haproxy.cfg template
# renders delayed too). But later recipes - identity, image, network,
# etc. - make keystone/glance/neutron API calls through the VIP while
# they converge (osl_openstack_role / _endpoint / _user ...). On a
# fresh bootstrap haproxy isn't listening yet, so the first run dies
# at osl_openstack_role with `Connection refused` on the VIP and the
# cluster needs several converges before the delayed start sticks.
#
# Render the (fully-accumulated) haproxy.cfg and start the service now.
# ip_nonlocal_bind (set above) lets haproxy bind the VIP before
# keepalived assigns it; keystone's backend isn't up until identity
# runs, so the listener just reports no server available until then -
# the os_conn retry loop rides that out. The template's own
# delayed_action :create and the delayed :start remain (idempotent).
#
# `not_if` keeps this idempotent: the eager bring-up only fires the
# first time, when haproxy isn't running yet. Once it's up, this is a
# no-op on every later converge (config changes still propagate via
# the haproxy cookbook's delayed template render + :reload). Without
# the guard the ruby_block would report "updated" every run and fail
# the second-converge idempotency check.
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
