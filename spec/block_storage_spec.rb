require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::block_storage' do
  let(:runner) { ChefSpec::SoloRunner.new(REDHAT_OPTS) }
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'identity_stubs'
  include_context 'block_storage_stubs'
  %w(
    firewall::iscsi
    osl-openstack
    openstack-block-storage::volume
    openstack-block-storage::identity_registration
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  before do
    node.set['osl-openstack']['cinder']['iscsi_role'] = 'iscsi_role'
    node.set['osl-openstack']['cinder']['iscsi_ips'] = %w(10.11.0.1)
    stub_search(:node, 'role:iscsi_role').and_return([{ ipaddress: '10.10.0.1' }])
  end

  it do
    expect(chef_run).to install_package('python2-crypto')
  end

  it do
    expect(chef_run).to upgrade_package('qemu-img-ev')
  end

  it 'adds iscsi nodes ipaddresses' do
    # TODO: Add a test that actually works with the node search
    expect(chef_run).to create_iptables_ng_rule('iscsi_ipv4').with(
      rule:
        [
          '--protocol tcp --source 10.11.0.1 --destination-port 3260 --jump ACCEPT',
          '--protocol tcp --source 127.0.0.1 --destination-port 3260 --jump ACCEPT'
        ],
      chain: 'iscsi'
    )
  end
end
