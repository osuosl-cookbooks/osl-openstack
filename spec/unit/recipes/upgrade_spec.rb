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
    expect(chef_run).to delete_yum_repository('RDO-mitaka')
  end
  it do
    expect(chef_run).to create_cookbook_file('/root/upgrade.sh')
      .with(source: 'upgrade-compute.sh', mode: 0755)
  end
  it do
    expect(chef_run).to run_ruby_block('raise_upgrade_exeception')
  end
  context 'controller type' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.set['osl-openstack']['node_type'] = 'controller'
        node.automatic['filesystem2']['by_mountpoint']
      end.converge(described_recipe)
    end
    it do
      expect(chef_run).to create_cookbook_file('/root/upgrade.sh')
        .with(source: 'upgrade-controller.sh', mode: 0755)
    end
  end
end
