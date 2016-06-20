require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::network' do
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
end
