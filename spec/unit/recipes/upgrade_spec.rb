require_relative '../../spec_helper'

describe 'osl-openstack::upgrade' do
  cached(:chef_run) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      node.automatic['filesystem2']['by_mountpoint']
    end.converge(described_recipe)
  end
  include_context 'identity_stubs'
  it 'converges successfully' do
    expect { chef_run }.to_not raise_error
  end
  it do
    expect(chef_run).to delete_yum_repository('RDO-queens')
  end
  it do
    expect(chef_run).to create_cookbook_file('/root/upgrade.sh')
      .with(source: 'upgrade-compute.sh', mode: '755')
  end
  it do
    expect(chef_run).to run_ruby_block('raise_upgrade_exeception')
  end
  context 'controller type' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.override['osl-openstack']['node_type'] = 'controller'
        node.automatic['filesystem2']['by_mountpoint']
      end.converge(described_recipe)
    end
    it do
      expect(chef_run).to include_recipe('openstack-identity::_fernet_tokens')
    end
    it do
      expect(chef_run).to create_file('/root/nova-cell-db-uri')
        .with(
          content: 'mysql+pymysql://nova_cell0_:keystone_db_pass@:3306/nova_cell0_?charset=utf8',
          mode: '600',
          sensitive: true
        )
    end
    it do
      expect(chef_run).to create_cookbook_file('/root/upgrade.sh')
        .with(source: 'upgrade-controller.sh', mode: '755')
    end
  end
  context '/root/upgrade-test exists' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.automatic['filesystem2']['by_mountpoint']
      end.converge(described_recipe)
    end
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('/root/upgrade-test').and_return(true)
    end
    it do
      expect(chef_run).to_not run_ruby_block('raise_upgrade_exeception')
    end
  end
  context '/root/rocky-upgrade-done exists' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.automatic['filesystem2']['by_mountpoint']
      end.converge(described_recipe)
    end
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('/root/rocky-upgrade-done').and_return(true)
    end
    it do
      expect(chef_run).to_not run_ruby_block('raise_upgrade_exeception')
    end
  end
  context '/root/upgrade-test and /root/rocky-upgrade-done exists' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.automatic['filesystem2']['by_mountpoint']
      end.converge(described_recipe)
    end
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('/root/rocky-upgrade-done').and_return(true)
      allow(File).to receive(:exist?).with('/root/upgrade-test').and_return(true)
    end
    it do
      expect(chef_run).to_not run_ruby_block('raise_upgrade_exeception')
    end
  end
end
