require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::compute', compute: true do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      # Work around for base::ifconfig:47
      node.automatic['virtualization']['system']
      node.set['osl-openstack']['physical_interface_mappings'] = {
        compute: 'eth1'
      }
    end
  end
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'identity_stubs'
  include_context 'compute_stubs'
  %w(
    firewall
    firewall::openstack
    firewall::vnc
    osl-openstack::default
    openstack-compute::compute
    openstack-telemetry::agent-compute
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  it 'loads tun module' do
    expect(chef_run).to save_modules('tun')
  end
  %w(ppc64 ppc64le).each do |a|
    context "setting arch to #{a}" do
      cached(:chef_run) { runner.converge(described_recipe) }
      before do
        node.automatic['kernel']['machine'] = a
      end
      context 'Setting as openstack guest' do
        let(:chef_run) { runner.converge(described_recipe) }
        before do
          node.automatic['cloud']['provider'] = 'openstack'
        end
        it 'loads kvm_pr module' do
          expect(chef_run).to save_modules('kvm_pr')
        end
      end
      it 'loads kvm_hv module' do
        expect(chef_run).to save_modules('kvm_hv')
      end
      it 'includes cookbook chef-sugar::default' do
        expect(chef_run).to include_recipe('chef-sugar::default')
      end
      it 'creates /etc/rc.d/rc.local' do
        expect(chef_run).to create_cookbook_file('/etc/rc.d/rc.local')
      end
      context 'SMT not enabled' do
        let(:chef_run) { runner.converge(described_recipe) }
        before do
          stub_command('/sbin/ppc64_cpu --smt 2>&1 | grep -E ' \
          "'SMT is off|Machine is not SMT capable'").and_return(true)
        end
        it 'Does not run ppc64_cpu_smt_off' do
          expect(chef_run).to_not run_execute('ppc64_cpu_smt_off')
        end
      end
      context 'SMT already enabled' do
        before do
          stub_command('/sbin/ppc64_cpu --smt 2>&1 | grep -E ' \
          "'SMT is off|Machine is not SMT capable'").and_return(false)
        end
        it 'Runs ppc64_cpu_smt_off' do
          expect(chef_run).to run_execute('ppc64_cpu_smt_off')
        end
      end
    end
  end
end
