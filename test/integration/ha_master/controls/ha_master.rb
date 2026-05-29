vip_v4 = '10.1.2.10'
vip_v6 = 'fd00:1:2::10'
vrrp_iface = 'ens4'

control 'keepalived' do
  describe service('keepalived') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'haproxy' do
  describe service('haproxy') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'ip_nonlocal_bind' do
  describe kernel_parameter('net.ipv4.ip_nonlocal_bind') do
    its('value') { should cmp 1 }
  end
  describe kernel_parameter('net.ipv6.ip_nonlocal_bind') do
    its('value') { should cmp 1 }
  end
end

control 'vip-held' do
  title 'Master holds the VIP'
  # CIDR matches the multinode data bag (vip_v4: 10.1.2.10/23,
  # vip_v6: fd00:1:2::10/64).
  describe command("ip -4 addr show dev #{vrrp_iface}") do
    its('stdout') { should match(%r{#{Regexp.escape(vip_v4)}/23}) }
  end
  describe command("ip -6 addr show dev #{vrrp_iface}") do
    its('stdout') { should match(%r{#{Regexp.escape(vip_v6)}/64}) }
  end
end

control 'haproxy-vip-listeners' do
  title 'HAProxy is listening on the VIP for the API ports'
  %w(5000 9292 8774 8778 9696 8776 8004 8000 6080 80 443).each do |p|
    describe port(p) do
      it { should be_listening }
      its('addresses') { should include vip_v4 }
    end
  end
end

control 'haproxy-tls-termination' do
  title 'haproxy terminates TLS for keystone / novnc / horizon-https'
  describe file('/etc/haproxy/certs/wildcard.pem') do
    it { should exist }
    it { should be_owned_by 'haproxy' }
    its('mode') { should cmp '0640' }
  end

  describe file('/etc/haproxy/haproxy.cfg') do
    # tls listeners
    its('content') { should match(%r{bind #{Regexp.escape(vip_v4)}:5000 ssl crt /etc/haproxy/certs/wildcard\.pem}) }
    its('content') { should match(%r{bind #{Regexp.escape(vip_v4)}:6080 ssl crt /etc/haproxy/certs/wildcard\.pem}) }
    its('content') { should match(%r{bind #{Regexp.escape(vip_v4)}:443 ssl crt /etc/haproxy/certs/wildcard\.pem}) }
    its('content') { should match(/option forwardfor/) }
    # plain-HTTP backends have no ssl crt
    its('content') { should match(/bind #{Regexp.escape(vip_v4)}:9292$/) }
    its('content') { should match(/bind #{Regexp.escape(vip_v4)}:9696$/) }
    # horizon-http (:80) is a redirect-only listener that 301s to https,
    # replacing Apache's wsgi-horizon http->https rewrite which is gated
    # off in HA mode.
    its('content') { should match(/^\s*http-request redirect scheme https code 301/) }
  end

  # Probe by canonical hostname (resolves to the VIP via /etc/hosts) so
  # the Host header matches keystone's vhost; hitting the bare IP would
  # trip the ServerAlias redirect and return 301 instead of 200.
  describe http('https://controller.testing.osuosl.org:5000/v3', ssl_verify: false) do
    its('status') { should cmp 200 }
  end
end

control 'memcached-cross-controller' do
  title 'memcached firewall lets the peer controller in (horizon sessions survive failover)'
  # osl_only sends the rule into the OSL CIDR chain - covers peer
  # controllers and compute nodes in one knob (mirrors AMQP).
  describe iptables do
    it { should have_rule('-A memcached -p tcp -m tcp --dport 11211 -j osl_only') }
  end
end

control 'mon-nrpe-checks-drop-ssl-on-ha' do
  title 'keystone and novnc nrpe checks omit --ssl in HA'
  # In HA the Apache backend serves plain HTTP for keystone and
  # nova-novncproxy serves plain ws on the per-host api_listen_ip
  # (10.1.2.3 for controller1 per the multinode data bag); haproxy on
  # the VIP is the TLS endpoint. The local check has to match what the
  # backend actually speaks, so --ssl must NOT be passed to check_http.
  {
    'check_keystone_api' => 5000,
    'check_novnc' => 6080,
  }.each do |name, port|
    describe file("/etc/nagios/nrpe.d/#{name}.cfg") do
      its('content') do
        should match(%r{^command\[#{name}\]=/usr/lib64/nagios/plugins/check_http -I 10\.1\.2\.3 -p #{port}$})
      end
      its('content') { should_not match(/--ssl/) }
    end
  end
end
