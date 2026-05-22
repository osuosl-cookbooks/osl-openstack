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
