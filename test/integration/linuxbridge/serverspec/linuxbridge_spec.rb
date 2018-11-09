require 'serverspec'

set :backend, :exec

describe service('neutron-linuxbridge-agent') do
  it { should be_enabled }
  it { should be_running }
end

[
  'tenant_network_type = gre,vxlan',
  'network_vlan_ranges = $',
].each do |s|
  describe file('/etc/neutron/plugins/ml2/linuxbridge_agent.ini') do
    its(:content) { should contain(/#{s}/).after(/^\[vlans\]/) }
  end
end
[
  'enable_vxlan = true',
  'l2_population = true',
  'local_ip = (?:[0-9]{1,3}\.){3}[0-9]{1,3}',
].each do |s|
  describe file('/etc/neutron/plugins/ml2/linuxbridge_agent.ini') do
    its(:content) { should contain(/#{s}/).after(/^\[vxlan\]/) }
  end
end

describe file('/etc/neutron/plugins/ml2/linuxbridge_agent.ini') do
  its(:content) do
    should contain(/polling_interval = 2/).after(/^\[agent\]/)
  end
  its(:content) do
    should contain(/physical_interface_mappings = public:eth1/)
      .after(/^\[linux_bridge\]/)
  end
  its(:content) do
    should contain(/firewall_driver = \
neutron.agent.linux.iptables_firewall.IptablesFirewallDriver/)
      .after(/^\[securitygroup\]/)
  end
end

describe command('systemctl list-dependencies --reverse neutron-linuxbridge-agent') do
  its(:stdout) { should contain(/iptables/) }
end
