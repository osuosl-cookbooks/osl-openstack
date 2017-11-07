require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::compute' do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      node.set['osl-openstack']['physical_interface_mappings'] = { compute: 'eth1' }
    end
  end
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  include_context 'compute_stubs'
  include_context 'linuxbridge_stubs'
  include_context 'network_stubs'
  include_context 'telemetry_stubs'
  %w(
    firewall
    firewall::openstack
    firewall::vnc
    osl-openstack::default
    osl-openstack::linuxbridge
    openstack-compute::compute
    openstack-telemetry::agent-compute
    ibm-power::default
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end

  it 'loads tun module' do
    expect(chef_run).to load_kernel_module('tun')
  end
  it do
    expect(chef_run).to create_template('/etc/sysconfig/libvirt-guests')
      .with(
        variables: {
          libvirt_guests: { 'on_boot' => 'ignore', 'on_shutdown' => 'shutdown', 'parallel_shutdown' => '25' }
        }
      )
  end
  [
    /^ON_BOOT=ignore$/,
    /^ON_SHUTDOWN=shutdown$/,
    /^PARALLEL_SHUTDOWN=25$/
  ].each do |line|
    it do
      expect(chef_run).to render_file('/etc/sysconfig/libvirt-guests').with_content(line)
    end
  end
  it do
    expect(chef_run).to enable_service('libvirt-guests')
  end
  it do
    expect(chef_run).to start_service('libvirt-guests')
  end
  it do
    expect(chef_run).to create_user_account('nova')
      .with(
        system_user: true,
        manage_home: false,
        ssh_keygen: false,
        ssh_keys: ['ssh public key']
      )
  end
  it do
    expect(chef_run).to create_file('/var/lib/nova/.ssh/id_rsa')
      .with(
        content: 'private ssh key',
        sensitive: true,
        user: 'nova',
        group: 'nova',
        mode: 0600
      )
  end
  it do
    expect(chef_run).to create_file('/var/lib/nova/.ssh/config')
      .with(
        user: 'nova',
        group: 'nova',
        mode: 0600,
        content: <<-EOL
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
        EOL
      )
  end

  context 'setting arch to ppc64le' do
    cached(:chef_run) { runner.converge(described_recipe) }
    before do
      node.automatic['kernel']['machine'] = 'ppc64le'
    end
    context 'Setting as openstack guest' do
      cached(:chef_run) { runner.converge(described_recipe) }
      before do
        node.automatic['cloud']['provider'] = 'openstack'
      end
      it 'loads kvm_pr module' do
        expect(chef_run).to load_kernel_module('kvm_pr')
      end
    end
    it 'loads kvm_hv module' do
      expect(chef_run).to load_kernel_module('kvm_hv')
    end
    it 'includes cookbook chef-sugar::default' do
      expect(chef_run).to include_recipe('chef-sugar::default')
    end
    it 'creates /etc/rc.d/rc.local' do
      expect(chef_run).to create_cookbook_file('/etc/rc.d/rc.local')
    end
    context 'SMT not enabled' do
      cached(:chef_run) { runner.converge(described_recipe) }
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
