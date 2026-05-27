control 'keepalived' do
  describe service('keepalived') do
    it { should be_enabled }
    it { should be_running }
  end

  describe processes('keepalived') do
    its('count') { should be > 0 }
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

control 'vip-bound' do
  # Single-node test: this node is master and should hold the VIPs.
  # CIDR matches the data bag (vip_v4: 192.168.60.10/24, vip_v6:
  # fc00::10/64) - keepalived honors the supplied prefix length.
  describe command('ip -4 addr show dev eth1') do
    its('stdout') { should match(%r{192\.168\.60\.10/24}) }
  end
  describe command('ip -6 addr show dev eth1') do
    its('stdout') { should match(%r{fc00::10/64}) }
  end
end

control 'haproxy' do
  describe service('haproxy') do
    it { should be_enabled }
    it { should be_running }
  end

  describe file('/etc/haproxy/haproxy.cfg') do
    it { should exist }
    its('content') { should match(/^listen keystone/) }
    its('content') { should match(/^listen horizon-https/) }
    # TLS listeners (keystone, novnc, horizon-https) terminate TLS on
    # haproxy via `ssl crt ...` on the bind. Plain-HTTP backends
    # (glance / nova / neutron / cinder / heat) stay in tcp mode and
    # have no ssl options.
    its('content') { should match(%r{bind 192\.168\.60\.10:5000 ssl crt /etc/haproxy/certs/wildcard\.pem}) }
    its('content') { should match(%r{bind \[fc00::10\]:5000 ssl crt /etc/haproxy/certs/wildcard\.pem}) }
    its('content') { should match(/bind 192\.168\.60\.10:9292$/) } # glance, no ssl
    its('content') { should match(/option forwardfor/) }
    its('content') { should match(/balance source/) }       # horizon
    its('content') { should match(/balance roundrobin/) }   # everything else
  end
end

control 'haproxy-cert-bundle' do
  describe file('/etc/haproxy/certs') do
    it { should be_directory }
    it { should be_owned_by 'haproxy' }
    its('mode') { should cmp '0700' }
  end

  describe file('/etc/haproxy/certs/wildcard.pem') do
    it { should exist }
    it { should be_owned_by 'haproxy' }
    its('mode') { should cmp '0640' }
    # cert + chain + key all in one PEM
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
  # Sanity-check a representative spread of the API ports HAProxy must
  # bind on the VIP. ip_nonlocal_bind=1 lets it bind even when the VIP
  # isn't held; in this test the local node is master so it is held.
  %w(5000 9292 8774 8778 9696 8776 8004 8000 6080 80 443).each do |p|
    describe command("ss -tlnp | awk '{print $4}' | grep -E '192\\.168\\.60\\.10:#{p}$|\\[fc00::10\\]:#{p}$'") do
      its('stdout') { should match(/192\.168\.60\.10:#{p}|\[fc00::10\]:#{p}/) }
    end
  end
end
