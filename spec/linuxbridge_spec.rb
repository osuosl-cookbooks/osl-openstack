require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::linuxbridge', linuxbridge: true do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      # Work around for base::ifconfig:47
      node.automatic['virtualization']['system']
    end
  end
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'identity_stubs'
  include_context 'network_stubs'
  include_context 'linuxbridge_stubs'
  %w(
    osl-openstack
    openstack-network
    openstack-network::ml2_linuxbridge
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  describe '/etc/neutron/plugins/ml2/linuxbridge_agent.ini' do
    let(:file) do
      chef_run.template('/etc/neutron/plugins/ml2/linuxbridge_agent.ini')
    end
    [
      /^tenant_network_type = gre,vxlan$/,
      /^network_vlan_ranges = $/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('vlans', line)
      end
    end
    [
      /^enable_security_group = True$/,
      /^firewall_driver = \
neutron.agent.linux.iptables_firewall.IptablesFirewallDriver$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('securitygroup', line)
      end
    end
    [
      /^enable_vxlan = true$/,
      /^l2_population = true$/,
      /^local_ip = (?:[0-9]{1,3}\.){3}[0-9]{1,3}$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('vxlan', line)
      end
    end
    context 'Setting controller vxlan_interface to eth1' do
      cached(:chef_run) { runner.converge(described_recipe) }
      before do
        node.set['osl-openstack']['node_type'] = 'controller'
        node.set['osl-openstack']['vxlan_interface']['controller'] = 'eth1'
        node.automatic['network']['interfaces']['eth1']['addresses'] = {
          '192.168.1.10' => {
            'family' => 'inet'
          }
        }
      end
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content(
            'vxlan',
            /^local_ip = 192.168.1.10$/
          )
      end
    end
    context 'Setting controller vxlan_interface to downed eth2' do
      cached(:chef_run) { runner.converge(described_recipe) }
      before do
        node.set['osl-openstack']['node_type'] = 'controller'
        node.set['osl-openstack']['vxlan_interface']['controller'] = 'eth2'
        node.automatic['network']['interfaces']['eth1']['addresses'] = {}
      end
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content(
            'vxlan',
            /^local_ip = 127.0.0.1$/
          )
      end
    end
    [
      /^polling_interval = 2$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('agent', line)
      end
    end
    context 'physical_interface_mappings is empty by default' do
      cached(:chef_run) { runner.converge(described_recipe) }
      [
        /^physical_interface_mappings = $/
      ].each do |line|
        before do
          node.set['osl-openstack']['physical_interface_mappings'] = []
        end
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content('linux_bridge', line)
        end
      end
    end
    context 'Create a public:eth1' do
      cached(:chef_run) { runner.converge(described_recipe) }
      [
        /^physical_interface_mappings = public:eth1$/
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content('linux_bridge', line)
        end
      end
    end
    context 'Create a public:eth2 on controller' do
      cached(:chef_run) { runner.converge(described_recipe) }
      before do
        node.set['osl-openstack']['node_type'] = 'controller'
      end
      [
        /^physical_interface_mappings = public:eth2$/
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content('linux_bridge', line)
        end
      end
    end
    context 'Create a public:eth1,private:eth2' do
      cached(:chef_run) { runner.converge(described_recipe) }
      before do
        node.set['osl-openstack']['physical_interface_mappings'] =
          [
            {
              name: 'public',
              controller: 'eth1',
              compute: 'eth1'
            },
            {
              name: 'private',
              controller: 'eth2',
              compute: 'eth2'
            }
          ]
      end
      [
        /^physical_interface_mappings = public:eth1,private:eth2$/
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content('linux_bridge', line)
        end
      end
    end
  end
end
