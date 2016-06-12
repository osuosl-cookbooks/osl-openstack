require_relative 'spec_helper'

describe 'osl-openstack::identity' do
  cached(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      # Work around for base::ifconfig:47
      node.automatic['virtualization']['system']
    end
  end
  cached(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'identity_stubs'
  %w(
    osl-openstack
    osl-openstack::ops_messaging
    openstack-identity::server-apache
    openstack-identity::registration
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
end
