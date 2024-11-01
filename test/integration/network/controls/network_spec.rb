controller = input('controller')
db_endpoint = input('db_endpoint')
controller_endpoint = input('controller_endpoint')
physical_interface_mappings = input('physical_interface_mappings')

control 'network' do
  %w(
    neutron-dhcp-agent
    neutron-l3-agent
    neutron-metadata-agent
    neutron-metering-agent
    neutron-server
  ).each do |s|
    describe service(s) do
      it { should be_enabled }
      it { should be_running }
    end
  end if controller

  describe service('neutron-linuxbridge-agent') do
    it { should be_enabled }
    it { should be_running }
  end

  describe ini('/etc/neutron/plugins/ml2/linuxbridge_agent.ini') do
    its('agent.polling_interval') { should cmp '2' }
    its('linux_bridge.physical_interface_mappings') { should cmp physical_interface_mappings }
    its('securitygroup.enable_security_group') { should cmp 'true' }
    its('securitygroup.firewall_driver') { should cmp 'neutron.agent.linux.iptables_firewall.IptablesFirewallDriver' }
    its('vlans.network_vlan_ranges') { should cmp '' }
    its('vlans.tenant_network_type') { should cmp 'gre,vxlan' }
    its('vxlan.enable_vxlan') { should cmp 'true' }
    its('vxlan.l2_population') { should cmp 'true' }
    its('vxlan.local_ip') { should cmp '127.0.0.1' }
  end

  describe command('systemctl list-dependencies --reverse neutron-linuxbridge-agent') do
    its('stdout') { should include 'iptables' }
  end

  describe port('9696') do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should include '0.0.0.0' }
  end if controller

  describe ini('/etc/neutron/neutron.conf') do
    if controller
      its('database.connection') { should cmp "mysql+pymysql://neutron_x86:neutron@#{db_endpoint}:3306/neutron_x86" }
      its('DEFAULT.allow_overlapping_ips') { should cmp 'true' }
      its('DEFAULT.control_exchange') { should cmp 'neutron' }
      its('DEFAULT.core_plugin') { should cmp 'ml2' }
      its('DEFAULT.router_distributed') { should cmp 'false' }
      its('DEFAULT.service_plugins') { should cmp 'neutron.services.l3_router.l3_router_plugin.L3RouterPlugin,metering' }
      its('nova.auth_url') { should cmp 'https://controller.example.com:5000/v3' }
      its('nova.password') { should cmp 'nova' }
    end
    its('DEFAULT.auth_strategy') { should cmp 'keystone' }
    its('DEFAULT.transport_url') { should cmp "rabbit://openstack:openstack@#{controller_endpoint}:5672" }
    its('keystone_authtoken.auth_url') { should cmp 'https://controller.example.com:5000/v3' }
    its('keystone_authtoken.memcached_servers') { should cmp "#{controller_endpoint}:11211" }
    its('keystone_authtoken.password') { should cmp 'neutron' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'true' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('keystone_authtoken.www_authenticate_uri') { should cmp 'https://controller.example.com:5000/v3' }
  end

  describe ini('/etc/neutron/l3_agent.ini') do
    its('DEFAULT.interface_driver') { should cmp 'neutron.agent.linux.interface.BridgeInterfaceDriver' }
  end if controller

  describe ini('/etc/neutron/dhcp_agent.ini') do
    its('DEFAULT.interface_driver') { should cmp 'neutron.agent.linux.interface.BridgeInterfaceDriver' }
    its('DEFAULT.enable_isolated_metadata') { should cmp 'true' }
    its('DEFAULT.dhcp_lease_duration') { should cmp '600' }
  end if controller

  describe ini('/etc/neutron/metadata_agent.ini') do
    its('DEFAULT.nova_metadata_host') { should cmp controller_endpoint }
    its('DEFAULT.metadata_proxy_shared_secret') { should cmp '2SJh0RuO67KpZ63z' }
    its('cache.backend') { should cmp 'dogpile.cache.memcached' }
    its('cache.enabled') { should cmp 'true' }
    its('cache.memcache_servers') { should cmp "#{controller_endpoint}:11211" }
  end if controller

  describe ini('/etc/neutron/metering_agent.ini') do
    its('DEFAULT.interface_driver') { should cmp 'neutron.agent.linux.interface.BridgeInterfaceDriver' }
    its('DEFAULT.driver') { should cmp 'neutron.services.metering.drivers.iptables.iptables_driver.IptablesMeteringDriver' }
  end if controller

  describe ini('/etc/neutron/plugin.ini') do
    its('ml2.extension_drivers') { should cmp 'port_security' }
    its('ml2.mechanism_drivers') { should cmp 'linuxbridge,l2population' }
    its('ml2.tenant_network_types') { should cmp 'vxlan' }
    its('ml2.type_drivers') { should cmp 'flat,vlan,vxlan' }
    its('ml2_type_flat.flat_networks') { should cmp '*' }
    its('ml2_type_gre.tunnel_id_ranges') { should cmp '32769:34000' }
    its('ml2_type_vlan.network_vlan_ranges') { should cmp '' }
    its('ml2_type_vxlan.vni_ranges') { should cmp '1:1000' }
  end if controller

  describe command('bash -c "source /root/openrc && neutron ext-list -c alias -f value"') do
    %w(
      address-scope
      agent
      allowed-address-pairs
      auto-allocated-topology
      availability_zone
      binding
      default-subnetpools
      dhcp_agent_scheduler
      dvr
      external-net
      ext-gw-mode
      extra_dhcp_opt
      extraroute
      flavors
      l3_agent_scheduler
      l3-flavors
      l3-ha
      metering
      multi-provider
      net-mtu
      network_availability_zone
      network-ip-availability
      pagination
      port-security
      project-id
      provider
      quotas
      rbac-policies
      router
      router_availability_zone
      security-group
      service-type
      sorting
      standard-attr-description
      standard-attr-revisions
      standard-attr-timestamp
      subnet_allocation
      subnet-service-types
    ).each do |ext|
      its('stdout') { should match(/^#{ext}$/) }
    end
  end if controller
end
