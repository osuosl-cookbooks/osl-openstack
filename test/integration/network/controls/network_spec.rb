controller = input('controller')
db_endpoint = input('db_endpoint')
controller_endpoint = input('controller_endpoint')
physical_interface_mappings = input('physical_interface_mappings')
primary_controller = input('primary_controller')
# messaging_host = AMQP host (mq tier on multi-node); memcached_host =
# the memcached backend (controller1 on multi-node).
messaging_host = input('messaging_host')
messaging_port = input('messaging_port')
memcached_host = input('memcached_host')

control 'network' do
  %w(osuosl-openstack-neutron-agent osuosl-openstack-cli).each do |p|
    describe package p do
      it { should be_installed }
    end
  end

  describe package 'osuosl-openstack-neutron-controller' do
    it { should be_installed }
  end if controller

  # The RPMs create these and seed the paste and rootwrap configs from the venv
  %w(/etc/neutron /etc/neutron/plugins/ml2).each do |d|
    describe directory d do
      its('owner') { should eq 'root' }
      its('group') { should eq 'neutron' }
      its('mode') { should cmp '0750' }
    end
  end

  %w(api-paste.ini rootwrap.conf).each do |f|
    describe file "/etc/neutron/#{f}" do
      it { should exist }
    end
  end

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
    its('AGENT.polling_interval') { should cmp '2' }
    its('AGENT.root_helper') { should cmp 'sudo /opt/openstack/neutron-agent/bin/neutron-rootwrap /etc/neutron/rootwrap.conf' }
    its('privsep.helper_command') { should cmp 'sudo /opt/openstack/neutron-agent/bin/privsep-helper' }
    its('linux_bridge.physical_interface_mappings') { should cmp physical_interface_mappings }
    its('securitygroup.enable_security_group') { should cmp 'true' }
    its('securitygroup.firewall_driver') { should cmp 'neutron.agent.linux.iptables_firewall.IptablesFirewallDriver' }
    its('vlans') { should be_nil }
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
  end if controller

  neutron_venv = controller ? '/opt/openstack/neutron-controller' : '/opt/openstack/neutron-agent'

  describe ini('/etc/neutron/neutron.conf') do
    its('AGENT.root_helper') { should cmp "sudo #{neutron_venv}/bin/neutron-rootwrap /etc/neutron/rootwrap.conf" }
    its('privsep_namespace.helper_command') { should cmp "sudo #{neutron_venv}/bin/privsep-helper" }
    if controller
      its('database.connection') { should cmp "mysql+pymysql://neutron_x86:neutron@#{db_endpoint}:3306/neutron_x86" }
      its('DEFAULT.allow_overlapping_ips') { should be_nil }
      its('experimental.linuxbridge') { should cmp 'true' }
      its('DEFAULT.control_exchange') { should cmp 'neutron' }
      its('DEFAULT.core_plugin') { should cmp 'ml2' }
      its('DEFAULT.router_distributed') { should cmp 'false' }
      its('DEFAULT.service_plugins') { should cmp 'neutron.services.l3_router.l3_router_plugin.L3RouterPlugin,metering' }
      its('nova.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
      its('nova.password') { should cmp 'nova' }
    end
    its('DEFAULT.auth_strategy') { should cmp 'keystone' }
    its('DEFAULT.transport_url') { should match(%r{^rabbit://openstack:openstack@#{Regexp.escape(messaging_host)}:#{messaging_port}}) }
    its('keystone_authtoken.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('keystone_authtoken.memcached_servers') { should match(/#{Regexp.escape(memcached_host)}:11211/) }
    its('keystone_authtoken.password') { should cmp 'neutron' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'true' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('keystone_authtoken.www_authenticate_uri') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
  end

  describe ini('/etc/neutron/l3_agent.ini') do
    its('DEFAULT.interface_driver') { should cmp 'neutron.agent.linux.interface.BridgeInterfaceDriver' }
  end if controller

  describe ini('/etc/neutron/dhcp_agent.ini') do
    its('DEFAULT.interface_driver') { should cmp 'neutron.agent.linux.interface.BridgeInterfaceDriver' }
    its('DEFAULT.enable_isolated_metadata') { should cmp 'true' }
    its('DEFAULT.dhcp_lease_duration') { should cmp '3600' }
  end if controller

  describe ini('/etc/neutron/metadata_agent.ini') do
    its('DEFAULT.nova_metadata_host') { should cmp controller_endpoint }
    its('DEFAULT.metadata_proxy_shared_secret') { should cmp '2SJh0RuO67KpZ63z' }
    its('cache.backend') { should cmp 'dogpile.cache.memcached' }
    its('cache.enabled') { should cmp 'true' }
    its('cache.memcache_servers') { should match(/#{Regexp.escape(memcached_host)}:11211/) }
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

  # osuosl-openstack-cli ships no deprecated neutron CLI
  describe command('bash -c "source /root/openrc && /usr/bin/openstack extension list --network -c Alias -f value"') do
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

  describe command('/root/create_network.sh') do
    its('exit_status') { should eq 0 }
    its('stderr') { should eq '' }
  end if controller && primary_controller

  # Each DHCP namespace needs a dnsmasq that, as the dnsmasq user, can re-read its
  # host file. Checked at run time: the test network only exists once verify starts
  dnsmasq_check = <<~'EOS'
    for i in $(seq 30); do
      nets=$(ip netns list | grep -oE "^qdhcp-[0-9a-f-]+" | sed "s/^qdhcp-//")
      if [ -n "$nets" ] || [ "$1" != true ]; then break; fi
      sleep 2
    done
    if [ -z "$nets" ] && [ "$1" = true ]; then echo "no qdhcp namespace"; exit 1; fi
    rc=0
    for net in $nets; do
      for i in $(seq 30); do pgrep -f "dnsmasq .*$net" >/dev/null && break; sleep 2; done
      pgrep -f "dnsmasq .*$net" >/dev/null || { echo "no dnsmasq for $net"; rc=1; continue; }
      runuser -u dnsmasq -- test -r "/var/lib/neutron/dhcp/$net/host" || { echo "dnsmasq cannot read $net/host"; rc=1; }
    done
    exit $rc
  EOS

  describe command("bash -c '#{dnsmasq_check}' _ #{primary_controller}") do
    its('exit_status') { should eq 0 }
    its('stdout') { should eq '' }
  end if controller

  describe command('bash -c "source /root/openrc && openstack network show public -c admin_state_up -c provider:network_type -c provider:physical_network -c router:external -c is_default -c shared -c status -f shell"') do
    its('stdout') { should match(/admin_state_up="True"/) }
    its('stdout') { should match(/is_default="True"/) }
    its('stdout') { should match(/provider_network_type="flat"/) }
    its('stdout') { should match(/provider_physical_network="public"/) }
    its('stdout') { should match(/router_external="True"/) }
    its('stdout') { should match(/shared="True"/) }
    its('stdout') { should match(/status="ACTIVE"/) }
  end if controller

  describe command('bash -c "source /root/openrc && openstack subnet show public -c allocation_pools -c cidr -c dns_nameservers -c gateway_ip -f shell"') do
    its('stdout') { should match(/allocation_pools="\[{'start': '10.10.1.2', 'end': '10.10.1.100'}\]"/) }
    its('stdout') { should match(%r{cidr="10.10.1.0/24"}) }
    its('stdout') { should match(/dns_nameservers="\['140.211.166.130', '140.211.166.131'\]"/) }
    its('stdout') { should match(/gateway_ip="10.10.1.1"/) }
  end if controller
end

# The keepalived primary records each package version it synced; other controllers sync nothing
control 'network-db-sync' do
  primary = input('primary_controller', value: true)
  { 'neutron' => 'osuosl-openstack-neutron-controller' }.each do |svc, pkg|
    evr = command("rpm -q --qf '%{EPOCH}:%{VERSION}-%{RELEASE}' #{pkg}").stdout
    describe file("/var/lib/osl-openstack/db-sync/#{svc}") do
      if primary
        its('content') { should cmp evr }
      else
        it { should_not exist }
      end
    end
  end
end if controller
