require 'serverspec'

set :backend, :exec

%w(
  neutron-dhcp-agent
  neutron-l3-agent
  neutron-linuxbridge-agent
  neutron-metadata-agent
  neutron-server
).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

describe port('9696') do
  it { should be_listening.with('tcp') }
end

[
  'service_plugins = ' \
  'neutron.services.l3_router.l3_router_plugin.L3RouterPlugin',
  'allow_overlapping_ips = True',
  'router_distributed = False'
].each do |s|
  describe file('/etc/neutron/neutron.conf') do
    its(:content) { should contain(/#{s}/).after(/^\[DEFAULT\]/) }
  end
end

%w(
  neutron.conf
  l3_agent.ini
  dhcp_agent.ini
).each do |f|
  describe file("/etc/neutron/#{f}") do
    its(:content) do
      should contain(/memcached_servers = .*:11211/)
        .after(/^\[DEFAULT\]/)
    end
    its(:content) do
      should contain(/memcached_servers = .*:11211/)
        .after(/^\[keystone_authtoken\]/)
    end
  end
end

[
  'interface_driver = neutron.agent.linux.interface.BridgeInterfaceDriver',
  'external_network_bridge = $'
].each do |s|
  describe file('/etc/neutron/l3_agent.ini') do
    its(:content) { should contain(/#{s}/).after(/^\[DEFAULT\]/) }
  end
end

[
  'interface_driver = neutron.agent.linux.interface.BridgeInterfaceDriver',
  'enable_isolated_metadata = True'
].each do |s|
  describe file('/etc/neutron/dhcp_agent.ini') do
    its(:content) { should contain(/#{s}/).after(/^\[DEFAULT\]/) }
  end
end

[
  'type_drivers = flat,vlan,vxlan',
  'extension_drivers = port_security',
  'tenant_network_types = vxlan',
  'mechanism_drivers = linuxbridge,l2population'
].each do |s|
  describe file('/etc/neutron/plugin.ini') do
    its(:content) { should contain(/#{s}/).after(/^\[ml2\]/) }
  end
end
[
  'enable_vxlan = true',
  'l2_population = true',
  'local_ip = (?:[0-9]{1,3}\.){3}[0-9]{1,3}'
].each do |s|
  describe file('/etc/neutron/plugins/ml2/linuxbridge_agent.ini') do
    its(:content) { should contain(/#{s}/).after(/^\[vxlan\]/) }
  end
end

describe file('/etc/neutron/plugins/ml2/linuxbridge_agent.ini') do
  its(:content) do
    should contain(/tenant_network_type = gre,vxlan/).after(/^\[vlans\]/)
  end
  its(:content) do
    should contain(/polling_interval = 2/).after(/^\[agent\]/)
  end
end

describe file('/etc/neutron/plugin.ini') do
  its(:content) do
    should contain(/flat_networks = */).after(/\[ml2_type_flat\]/)
  end
  its(:content) do
    should contain(/network_vlan_ranges = $/).after(/\[ml2_type_vlan\]/)
  end
  its(:content) do
    should contain(/tunnel_id_ranges = 32769:34000/).after(/\[ml2_type_gre\]/)
  end
  its(:content) do
    should contain(/vni_ranges = 1:1000/).after(/\[ml2_type_vxlan\]/)
  end
end

describe command('source /root/openrc && neutron ext-list') do
  its(:stdout) do
    should contain(/l3_agent_scheduler/)
  end
end