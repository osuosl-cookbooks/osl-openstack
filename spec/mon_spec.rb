require_relative 'spec_helper'

describe 'osl-openstack::mon' do
  cached(:chef_run) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS).converge(described_recipe)
  end
  it 'converges successfully' do
    expect { chef_run }.to_not raise_error
  end
  it 'includes osl-nrpe recipe' do
    expect(chef_run).to include_recipe('osl-nrpe::default')
  end
  %w(ppc64 ppc64le).each do |a|
    context "Setting arch to #{a}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
          node.automatic['kernel']['machine'] = a
        end.converge(described_recipe)
      end
      it 'sets check_load warning attributes correctly' do
        total_cpu = chef_run.node['cpu']['total']
        expect(chef_run.node['osl-nrpe']['check_load']['warning']).to \
          eq("#{total_cpu * 4 + 10},#{total_cpu * 4 + 5},#{total_cpu * 4}")
      end
      it 'sets check_load critical attributes correctly' do
        total_cpu = chef_run.node['cpu']['total']
        expect(chef_run.node['osl-nrpe']['check_load']['critical']).to \
          eq("#{total_cpu * 8 + 10},#{total_cpu * 8 + 5},#{total_cpu * 8}")
      end
    end
  end
end
