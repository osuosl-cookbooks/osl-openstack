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
end

describe port('9696') do
  it { should be_listening }
  its('protocols') { should include 'tcp' }
  its('addresses') { should include '127.0.0.1' }
end

describe ini('/etc/neutron/neutron.conf') do
  its('DEFAULT.service_plugins') { should cmp 'neutron.services.l3_router.l3_router_plugin.L3RouterPlugin,metering' }
  its('DEFAULT.allow_overlapping_ips') { should cmp 'True' }
  its('DEFAULT.router_distributed') { should cmp 'False' }
end

%w(
  neutron.conf
  l3_agent.ini
  dhcp_agent.ini
).each do |f|
  describe ini("/etc/neutron/#{f}") do
    its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
    its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
  end
end

%w(l3_agent metering_agent).each do |f|
  describe ini("/etc/neutron/#{f}.ini") do
    its('DEFAULT.interface_driver') { should cmp 'neutron.agent.linux.interface.BridgeInterfaceDriver' }
  end
end

describe ini('/etc/neutron/dhcp_agent.ini') do
  its('DEFAULT.interface_driver') { should cmp 'neutron.agent.linux.interface.BridgeInterfaceDriver' }
  its('DEFAULT.enable_isolated_metadata') { should cmp 'True' }
  its('DEFAULT.dhcp_lease_duration') { should cmp '600' }
end

describe ini('/etc/neutron/metadata_agent.ini') do
  its('DEFAULT.nova_metadata_host') { should cmp '127.0.0.1' }
end

describe ini('/etc/neutron/plugin.ini') do
  its('ml2.type_drivers') { should cmp 'flat,vlan,vxlan' }
  its('ml2.extension_drivers') { should cmp 'port_security' }
  its('ml2.tenant_network_types') { should cmp 'vxlan' }
  its('ml2.mechanism_drivers') { should cmp 'linuxbridge,l2population' }
end

describe ini('/etc/neutron/plugin.ini') do
  its('ml2_type_flat.flat_networks') { should cmp '*' }
  its('ml2_type_vlan.network_vlan_ranges') { should cmp '' }
  its('ml2_type_gre.tunnel_id_ranges') { should cmp '32769:34000' }
  its('ml2_type_vxlan.vni_ranges') { should cmp '1:1000' }
end

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
    tag
    tag-ext
  ).each do |ext|
    its('stdout') { should match(/^#{ext}$/) }
  end
end
