vip_v4 = input('vip_v4')
vip_v6 = input('vip_v6')
vrrp_iface = input('vrrp_iface')
api_listen_ip = input('api_listen_ip')
cert = '/etc/haproxy/certs/wildcard.pem'

control 'keepalived' do
  describe service('keepalived') do
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

control 'vip' do
  title 'The master holds the VIP with the data bag prefix; the standby does not'
  if input('holds_vip')
    describe command("ip -4 addr show dev #{vrrp_iface}") do
      its('stdout') { should match(%r{#{Regexp.escape(vip_v4)}/#{input('vip_v4_prefix')}}) }
    end
    describe command("ip -6 addr show dev #{vrrp_iface}") do
      its('stdout') { should match(%r{#{Regexp.escape(vip_v6)}/#{input('vip_v6_prefix')}}) }
    end
  else
    describe command("ip -4 addr show dev #{vrrp_iface}") do
      its('stdout') { should_not match(/#{Regexp.escape(vip_v4)}\b/) }
    end
    describe command("ip -6 addr show dev #{vrrp_iface}") do
      its('stdout') { should_not match(/#{Regexp.escape(vip_v6)}\b/) }
    end
  end
end

control 'haproxy' do
  describe service('haproxy') do
    it { should be_enabled }
    it { should be_running }
  end

  describe file('/etc/haproxy/haproxy.cfg') do
    its('content') { should match(/^listen keystone/) }
    its('content') { should match(/^listen horizon-https/) }
    %w(5000 6080 443).each do |p|
      its('content') { should match(/bind #{Regexp.escape(vip_v4)}:#{p} ssl crt #{Regexp.escape(cert)}/) }
    end
    its('content') { should match(/bind \[#{Regexp.escape(vip_v6)}\]:5000 ssl crt #{Regexp.escape(cert)}/) }
    # Plain-HTTP backends stay in tcp mode with no ssl options
    its('content') { should match(/bind #{Regexp.escape(vip_v4)}:9292$/) }
    its('content') { should match(/bind #{Regexp.escape(vip_v4)}:9696$/) }
    its('content') { should match(/option forwardfor/) }
    its('content') { should match(/balance source/) }
    its('content') { should match(/balance roundrobin/) }
    its('content') { should match(/^\s*http-request redirect scheme https code 301/) }
    its('content') { should match(%r{acl throttle_exempt src 10\.0\.0\.0/8 127\.0\.0\.0/8 140\.211\.0\.0/16}) }
    its('content') { should match(/stick-table type ipv6 size 100k expire 10m store conn_rate\(10s\)/) }
    its('content') { should match(/tcp-request connection track-sc0 src if !throttle_exempt/) }
    its('content') { should match(/tcp-request connection reject if \{ sc0_conn_rate gt 50 \}/) }
  end
end

control 'haproxy-cert-bundle' do
  describe file('/etc/haproxy/certs') do
    it { should be_directory }
    it { should be_owned_by 'haproxy' }
    its('mode') { should cmp '0700' }
  end

  describe file(cert) do
    it { should be_owned_by 'haproxy' }
    its('mode') { should cmp '0640' }
    its('content') { should match(/-----BEGIN CERTIFICATE-----/) }
    its('content') { should match(/-----BEGIN (?:RSA )?PRIVATE KEY-----/) }
  end
end

control 'haproxy-stats' do
  describe port(9000) do
    it { should be_listening }
  end
end

control 'haproxy-vip-listeners' do
  title 'HAProxy binds every API port on the VIP, held or not'
  %w(5000 9292 8774 8778 9696 8776 8004 8000 6080 80 443).each do |p|
    describe command("ss -Hltn 'sport = :#{p}'") do
      its('stdout') { should match(/#{Regexp.escape(vip_v4)}:#{p}/) }
    end
  end
end

control 'keystone-via-vip' do
  title 'keystone answers through haproxy on the VIP'
  only_if('multi-node runs resolve the controller hostname to the VIP') { input('keystone_probe') }
  describe http('https://controller.testing.osuosl.org:5000/v3', ssl_verify: false) do
    its('status') { should cmp 200 }
  end
end

control 'mon-nrpe-checks-drop-ssl-on-ha' do
  title 'keystone and novnc nrpe checks omit --ssl in HA'
  { 'check_keystone_api' => 5000, 'check_novnc' => 6080 }.each do |name, port|
    describe file("/etc/nagios/nrpe.d/#{name}.cfg") do
      its('content') do
        should match(%r{^command\[#{name}\]=/usr/lib64/nagios/plugins/check_http -I #{Regexp.escape(api_listen_ip)} -p #{port}$})
      end
      its('content') { should_not match(/--ssl/) }
    end
  end
end
