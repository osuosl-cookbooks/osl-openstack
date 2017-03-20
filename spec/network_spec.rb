require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::network', network: true do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      # Work around for base::ifconfig:47
      node.automatic['virtualization']['system']
    end
  end
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  include_context 'network_stubs'
  include_context 'mellanox_stubs'
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
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  describe '/etc/neutron/neutron.conf' do
    let(:file) { chef_run.template('/etc/neutron/neutron.conf') }
    [
      /^service_plugins = \
neutron.services.l3_router.l3_router_plugin.L3RouterPlugin$/,
      /^allow_overlapping_ips = True$/,
      /^router_distributed = False$/,
      /^bind_host = 10.0.0.2$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('DEFAULT', line)
      end
    end
    context 'Set bind_service' do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
          node.set['osl-openstack']['bind_service'] = '192.168.1.1'
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
            %r{^auth_url = https://10.0.0.10:5000/v2.0$}
          )
      end
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'database',
          %r{^connection = mysql://neutron_x86:neutron@10.0.0.10:3306/\
neutron_x86\?charset=utf8}
        )
    end
  end

  describe '/etc/neutron/l3_agent.ini' do
    let(:file) { chef_run.template('/etc/neutron/l3_agent.ini') }
    [
      /^interface_driver = \
neutron.agent.linux.interface.BridgeInterfaceDriver$/,
      /^external_network_bridge = $/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('DEFAULT', line)
      end
    end
  end

  describe '/etc/neutron/dhcp_agent.ini' do
    let(:file) { chef_run.template('/etc/neutron/dhcp_agent.ini') }
    [
      /^interface_driver = \
neutron.agent.linux.interface.BridgeInterfaceDriver$/,
      /^enable_isolated_metadata = True/,
      /^dhcp_lease_duration = 120/
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
      /^mechanism_drivers = linuxbridge,l2population$/
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
    context 'ml2_mlnx enabled' do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
          # Work around for base::ifconfig:47
          node.automatic['virtualization']['system']
          node.set['osl-openstack']['ml2_mlnx']['enabled'] = true
        end.converge(described_recipe)
      end
      [
        %r{^url = https://localhost/neo/$},
        /^username = admin/,
        /^password = password/,
        /^domain = cloudx$/
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content('sdn', line)
        end
      end
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('ml2', /^mechanism_drivers = sdnmechdriver,linuxbridge,sriovnicswitch,l2population$/)
      end
    end
  end
  describe '/etc/neutron/metadata_agent.ini' do
    let(:file) { chef_run.template('/etc/neutron/metadata_agent.ini') }
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content('DEFAULT', /^nova_metadata_ip = 10.0.0.2$/)
    end
  end
  %w(
    neutron.conf
    l3_agent.ini
    dhcp_agent.ini
    metadata_agent.ini
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
        /^memcache_servers = 10.0.0.10:11211$/
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content('cache', line)
        end
      end

      [
        /^rabbit_host = 10.0.0.10$/,
        /^rabbit_userid = guest$/,
        /^rabbit_password = mq-pass$/
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content('oslo_messaging_rabbit', line)
        end
      end
    end
  end
end
