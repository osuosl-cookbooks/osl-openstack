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
    node.normal['osl-openstack']['cinder']['iscsi_role'] = 'iscsi_role'
    node.normal['osl-openstack']['cinder']['iscsi_ips'] = %w(10.11.0.1)
    node.automatic['filesystem2']['by_mountpoint']
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
          '--protocol tcp --source 10.10.0.1 --destination-port 3260 --jump ACCEPT',
          '--protocol tcp --source 10.11.0.1 --destination-port 3260 --jump ACCEPT',
          '--protocol tcp --source 127.0.0.1 --destination-port 3260 --jump ACCEPT',
        ],
      chain: 'iscsi'
    )
  end
  context 'Set ceph' do
    let(:runner) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.normal['osl-openstack']['ceph'] = true
        node.automatic['filesystem2']['by_mountpoint']
      end
    end
    let(:node) { runner.node }
    cached(:chef_run) { runner.converge(described_recipe) }
    include_context 'common_stubs'
    include_context 'ceph_stubs'
    it do
      expect(chef_run).to include_recipe('osl-openstack::_block_ceph')
    end
    it do
      expect(chef_run).to install_package('openstack-cinder')
    end
    it do
      expect(chef_run).to modify_group('ceph-block')
        .with(
          group_name: 'ceph',
          append: true,
          members: %w(cinder)
        )
    end
    it do
      expect(chef_run.group('ceph-block')).to notify('service[cinder-volume]').to(:restart).immediately
    end
    it do
      expect(chef_run.template('/etc/ceph/ceph.client.cinder.keyring')).to notify('service[cinder-volume]')
        .to(:restart).immediately
    end
    it do
      expect(chef_run).to create_template('/etc/ceph/ceph.client.cinder.keyring')
        .with(
          source: 'ceph.client.keyring.erb',
          owner: 'ceph',
          group: 'ceph',
          sensitive: true,
          variables: {
            ceph_user: 'cinder',
            ceph_token: 'block_token',
          }
        )
    end
    it do
      expect(chef_run).to create_template('/etc/ceph/ceph.client.cinder-backup.keyring')
        .with(
          source: 'ceph.client.keyring.erb',
          owner: 'ceph',
          group: 'ceph',
          sensitive: true,
          variables: {
            ceph_user: 'cinder-backup',
            ceph_token: 'block_backup_token',
          }
        )
    end
    it do
      expect(chef_run).to edit_replace_or_add('log-dir storage')
        .with(
          path: '/usr/share/cinder/cinder-dist.conf',
          pattern: '^logdir.*',
          replace_only: true,
          backup: true
        )
    end
    it do
      expect(chef_run.replace_or_add('log-dir storage')).to notify('service[cinder-volume]').to(:restart)
    end
  end
end
