require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::network', network: true do
  let(:runner) { ChefSpec::SoloRunner.new(REDHAT_OPTS) }
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  include_context 'network_stubs'
  %w(
    osl-openstack
    firewall::openstack
    openstack-network::identity_registration
    openstack-network::ml2_core_plugin
    openstack-network::ml2_linuxbridge
    openstack-network
    openstack-network::plugin_config
    openstack-network::server
    openstack-network::l3_agent
    openstack-network::dhcp_agent
    openstack-network::metadata_agent
    openstack-network::metering_agent
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  context 'Set subnet and uuid in physical_interface_mappings' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.normal['osl-openstack']['physical_interface_mappings'] =
          [
            {
              name: 'public',
              subnet: '10.0.0.0/24',
              uuid: '4c948996-d603-4263-bcd8-fa5ade80bed8',
              controller: { default: 'eth1' },
              compute: { default: 'eth1' },
            },
            {
              name: 'backend',
              controller: { default: 'eth1' },
              compute: { default: 'eth1' },
            },
          ]
        node.automatic['filesystem2']['by_mountpoint']
      end.converge(described_recipe)
    end
    before do
      ip_cmd = 'ip netns exec qdhcp-4c948996-d603-4263-bcd8-fa5ade80bed8'
      stub_command("#{ip_cmd} iptables -S | egrep \"10.0.0.0/24.*port 53.*DROP\"").and_return(false)
    end
    it do
      expect(chef_run).to run_bash('block external dns on public')
        .with(
          code: <<-EOL
ip netns exec qdhcp-4c948996-d603-4263-bcd8-fa5ade80bed8 iptables -A INPUT -p tcp --dport 53 ! -s 10.0.0.0/24 -j DROP
ip netns exec qdhcp-4c948996-d603-4263-bcd8-fa5ade80bed8 iptables -A INPUT -p udp --dport 53 ! -s 10.0.0.0/24 -j DROP
EOL
        )
    end
  end
  describe '/etc/neutron/neutron.conf' do
    let(:file) { chef_run.template('/etc/neutron/neutron.conf') }
    [
      /^service_plugins = neutron.services.l3_router.l3_router_plugin.L3RouterPlugin,metering$/,
      /^allow_overlapping_ips = True$/,
      /^router_distributed = False$/,
      /^bind_host = 10.0.0.2$/,
      %r{^transport_url = rabbit://openstack:mq-pass@10.0.0.10:5672$},
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('DEFAULT', line)
      end
    end
    context 'Set bind_service' do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
          node.normal['osl-openstack']['bind_service'] = '192.168.1.1'
          node.automatic['filesystem2']['by_mountpoint']
        end.converge(described_recipe)
      end
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content(
            'DEFAULT',
            /^bind_host = 192.168.1.1$/
          )
      end
    end
    %w(keystone_authtoken nova).each do |s|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content(
            s,
            %r{^auth_url = https://10.0.0.10:5000/v3$}
          )
      end
      case s
      when 'keystone_authtoken'
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content(
              s,
              %r{^www_authenticate_uri = https://10.0.0.10:5000/v3$}
            )
        end
      end
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'database',
          %r{^connection = mysql\+pymysql://neutron_x86:neutron@10.0.0.10:3306/neutron_x86\?charset=utf8}
        )
    end
  end

  describe '/etc/neutron/l3_agent.ini' do
    let(:file) { chef_run.template('/etc/neutron/l3_agent.ini') }
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'DEFAULT',
          /^interface_driver = neutron.agent.linux.interface.BridgeInterfaceDriver$/
        )
    end
    it do
      expect(chef_run).to_not render_config_file(file.name).with_section_content('DEFAULT', /^external_network_bridge/)
    end
  end

  describe '/etc/neutron/dhcp_agent.ini' do
    let(:file) { chef_run.template('/etc/neutron/dhcp_agent.ini') }
    [
      /^interface_driver = \
neutron.agent.linux.interface.BridgeInterfaceDriver$/,
      /^enable_isolated_metadata = True/,
      /^dhcp_lease_duration = 600/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('DEFAULT', line)
      end
    end
  end
  describe '/etc/neutron/plugin.ini' do
    let(:file) { chef_run.template('/etc/neutron/plugin.ini') }
    [
      /^type_drivers = flat,vlan,vxlan$/,
      /^extension_drivers = port_security$/,
      /^tenant_network_types = vxlan$/,
      /^mechanism_drivers = linuxbridge,l2population$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('ml2', line)
      end
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content('ml2_type_flat', /^flat_networks = \*$/)
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content('ml2_type_vlan', /^network_vlan_ranges = $/)
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'ml2_type_gre',
          /^tunnel_id_ranges = 32769:34000$/
        )
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content('ml2_type_vxlan', /^vni_ranges = 1:1000$/)
    end
  end
  describe '/etc/neutron/metadata_agent.ini' do
    let(:file) { chef_run.template('/etc/neutron/metadata_agent.ini') }
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content('DEFAULT', /^nova_metadata_host = 10.0.0.2$/)
    end
  end
  describe '/etc/neutron/metering_agent.ini' do
    let(:file) { chef_run.template('/etc/neutron/metering_agent.ini') }
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content('DEFAULT', /^interface_driver = neutron.agent.linux.interface.BridgeInterfaceDriver$/)
    end
  end
  %w(
    neutron.conf
    l3_agent.ini
    dhcp_agent.ini
    metering_agent.ini
  ).each do |f|
    describe "/etc/neutron/#{f}" do
      let(:file) { chef_run.template("/etc/neutron/#{f}") }
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content(
            'keystone_authtoken',
            /^memcached_servers = 10.0.0.10:11211$/
          )
      end

      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content(
            'oslo_messaging_notifications',
            /^driver = messagingv2$/
          )
      end

      [
        /^backend = oslo_cache.memcache_pool$/,
        /^enabled = true$/,
        /^memcache_servers = 10.0.0.10:11211$/,
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content('cache', line)
        end
      end
    end
  end
end
