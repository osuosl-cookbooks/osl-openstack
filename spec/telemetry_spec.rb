require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::telemetry', telemetry: true do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      # Work around for base::ifconfig:47
      node.automatic['virtualization']['system']
    end
  end
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'identity_stubs'
  include_context 'telemetry_stubs'
  %w(
    osl-openstack
    openstack-telemetry::api
    openstack-telemetry::agent-central
    openstack-telemetry::agent-notification
    openstack-telemetry::collector
    openstack-telemetry::identity_registration
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
end
