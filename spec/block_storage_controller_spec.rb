require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::block_storage_controller' do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      # Work around for base::ifconfig:47
      node.automatic['virtualization']['system']
    end
  end
  let(:node) { runner.node }
  let(:chef_run) { runner.converge(described_recipe) }
  include_context 'identity_stubs'
  include_context 'block_storage_stubs'
  %w(
    osl-openstack
    firewall::openstack
    openstack-block-storage::api
    openstack-block-storage::scheduler
    openstack-block-storage::identity_registration
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
end
