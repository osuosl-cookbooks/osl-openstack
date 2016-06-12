require_relative 'spec_helper'

describe 'osl-openstack::ops_messaging' do
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
    firewall::amqp
    firewall::rabbitmq_mgt
    openstack-ops-messaging::rabbitmq-server
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
end
