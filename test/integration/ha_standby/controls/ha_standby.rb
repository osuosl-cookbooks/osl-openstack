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

control 'vip-not-held' do
  title 'Standby does not hold the VIP'
  # Whatever CIDR the master ends up with (10.1.2.10/23 from the
  # multinode data bag), it must NOT be present on the standby.
  describe command("ip -4 addr show dev #{vrrp_iface}") do
    its('stdout') { should_not match(/#{Regexp.escape(vip_v4)}\b/) }
  end
  describe command("ip -6 addr show dev #{vrrp_iface}") do
    its('stdout') { should_not match(/#{Regexp.escape(vip_v6)}\b/) }
  end
end

control 'haproxy-vip-binds' do
  title 'HAProxy still binds the VIP ports (ip_nonlocal_bind=1) so failover is instant'
  # ss -tln will show the bound socket on the VIP even when this node
  # doesn't currently hold the address.
  %w(5000 9292 8774 8778 9696 8776 8004 8000 6080 80 443).each do |p|
    describe command("ss -Hltn 'sport = :#{p}'") do
      its('stdout') { should match(/#{Regexp.escape(vip_v4)}:#{p}/) }
    end
  end
end
