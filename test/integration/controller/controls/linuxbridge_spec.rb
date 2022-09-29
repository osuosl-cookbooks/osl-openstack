describe service('neutron-linuxbridge-agent') do
  it { should be_enabled }
  it { should be_running }
end

describe ini('/etc/neutron/plugins/ml2/linuxbridge_agent.ini') do
  its('vlans.tenant_network_type') { should cmp 'gre,vxlan' }
  its('vlans.network_vlan_ranges') { should cmp '' }
  its('vxlan.enable_vxlan') { should cmp 'true' }
  its('vxlan.l2_population') { should cmp 'true' }
  its('vxlan.local_ip') { should match(/(?:[0-9]{1,3}\.){3}[0-9]{1,3}/) }
  its('agent.polling_interval') { should cmp '2' }
  its('linux_bridge.physical_interface_mappings') { should cmp 'public:eth1,private2:eth2' }
  its('securitygroup.enable_security_group') { should cmp 'True' }
  its('securitygroup.firewall_driver') { should cmp 'neutron.agent.linux.iptables_firewall.IptablesFirewallDriver' }
end

describe command('systemctl list-dependencies --reverse neutron-linuxbridge-agent') do
  its('stdout') { should include 'iptables' }
end
