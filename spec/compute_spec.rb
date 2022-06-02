require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::compute' do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      node.override['osl-openstack']['physical_interface_mappings'] = { compute: 'eth1' }
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
    osl-openstack::default
    osl-openstack::linuxbridge
    openstack-compute::compute
    openstack-telemetry::agent-compute
    ibm-power::default
  ).each do |r|
    it { expect(chef_run).to include_recipe(r) }
  end

  it { expect(chef_run).to accept_osl_firewall_openstack('osl-openstack') }
  it { expect(chef_run).to accept_osl_firewall_vnc('osl-openstack') }

  it do
    expect(chef_run).to edit_delete_lines('remove dhcpbridge on compute')
      .with(
        path: '/usr/share/nova/nova-dist.conf',
        pattern: '^dhcpbridge.*',
        backup: true
      )
  end

  it do
    expect(chef_run).to edit_delete_lines('remove force_dhcp_release on compute')
      .with(
        path: '/usr/share/nova/nova-dist.conf',
        pattern: '^force_dhcp_release.*',
        backup: true
      )
  end

  it { expect(chef_run.delete_lines('remove dhcpbridge on compute')).to notify('service[nova-compute]').to(:restart) }
  it { expect(chef_run.delete_lines('remove force_dhcp_release on compute')).to notify('service[nova-compute]').to(:restart) }
  it { expect(chef_run).to_not include_recipe('osl-openstack::_block_ceph') }
  it { expect(chef_run).to load_kernel_module('tun') }
  it do
    expect(chef_run).to create_template('/etc/sysconfig/libvirt-guests')
      .with(
        variables: {
          libvirt_guests: {
            'on_boot' => 'ignore',
            'on_shutdown' =>
            'shutdown',
            'parallel_shutdown' => '25',
            'shutdown_timeout' => '120',
          },
        }
      )
  end
  [
    /^ON_BOOT=ignore$/,
    /^ON_SHUTDOWN=shutdown$/,
    /^PARALLEL_SHUTDOWN=25$/,
    /^SHUTDOWN_TIMEOUT=120$/,
  ].each do |line|
    it { expect(chef_run).to render_file('/etc/sysconfig/libvirt-guests').with_content(line) }
  end
  it { expect(chef_run).to enable_service('libvirt-guests') }
  it { expect(chef_run).to start_service('libvirt-guests') }
  [
    /^max_clients = 200$/,
    /^max_workers = 200$/,
    /^max_requests = 200$/,
    /^max_client_requests = 50$/,
  ].each do |line|
    it { expect(chef_run).to render_file('/etc/libvirt/libvirtd.conf').with_content(line) }
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
        mode: '600'
      )
  end
  it do
    expect(chef_run).to create_file('/var/lib/nova/.ssh/config')
      .with(
        user: 'nova',
        group: 'nova',
        mode: '600',
        content: <<~EOL
          Host *
            StrictHostKeyChecking no
            UserKnownHostsFile /dev/null
                  EOL
      )
  end
  %w(libguestfs-tools python2-wsme).each do |p|
    it { expect(chef_run).to install_package(p) }
  end
  context 'Set ceph' do
    let(:runner) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.override['osl-openstack']['ceph']['compute'] = true
        node.override['osl-openstack']['ceph']['volume'] = true
        node.automatic['filesystem2']['by_mountpoint']
      end
    end
    let(:node) { runner.node }
    cached(:chef_run) { runner.converge(described_recipe) }
    include_context 'common_stubs'
    include_context 'ceph_stubs'
    before do
      stub_command('virsh secret-list | grep 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8').and_return(false)
      stub_command('virsh secret-get-value 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8 | grep block_token')
        .and_return(false)
    end
    %w(
      /var/run/ceph/guests
      /var/log/ceph
    ).each do |d|
      it { expect(chef_run).to create_directory(d).with(owner: 'qemu', group: 'libvirt') }
    end
    it { expect(chef_run).to include_recipe('osl-openstack::_block_ceph') }
    it do
      expect(chef_run).to modify_group('ceph-compute')
        .with(
          group_name: 'ceph',
          append: true,
          members: %w(nova qemu)
        )
    end
    it { expect(chef_run.group('ceph-compute')).to notify('service[nova-compute]').to(:restart).immediately }
    it { expect(chef_run.group('ceph-compute')).to_not notify('service[cinder-volume]').to(:restart).immediately }
    it do
      expect(chef_run.template('/etc/ceph/ceph.client.cinder.keyring')).to_not notify('service[cinder-volume]')
        .to(:restart).immediately
    end
    it do
      expect(chef_run).to create_template('/var/chef/cache/secret.xml')
        .with(
          source: 'secret.xml.erb',
          user: 'root',
          group: 'root',
          mode: '00600',
          variables: {
            uuid: '8102bb29-f48b-4f6e-81d7-4c59d80ec6b8',
            client_name: 'cinder',
          }
        )
    end
    it { expect(chef_run).to run_execute('virsh secret-define --file /var/chef/cache/secret.xml') }
    it do
      expect(chef_run).to run_execute('update virsh ceph secret')
        .with(
          command: 'virsh secret-set-value --secret 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8 --base64 block_token',
          sensitive: true
        )
    end
    it do
      expect(chef_run).to delete_file('/var/chef/cache/secret.xml')
    end
    [
      %r{^admin socket = /var/run/ceph/guests/\$cluster-\$type.\$id.\$pid.\$cctid.asok$},
      /^rbd concurrent management ops = 20$/,
      /^rbd cache = true$/,
      /^rbd cache writethrough until flush = true$/,
      %r{log file = /var/log/ceph/qemu-guest-\$pid.log$},
    ].each do |line|
      it { expect(chef_run).to render_config_file('/etc/ceph/ceph.conf').with_section_content('client', line) }
    end
    context 'virsh secret exists' do
      let(:runner) do
        ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
          node.override['osl-openstack']['ceph']['compute'] = true
          node.automatic['filesystem2']['by_mountpoint']
        end
      end
      let(:node) { runner.node }
      cached(:chef_run) { runner.converge(described_recipe) }
      include_context 'common_stubs'
      include_context 'ceph_stubs'
      before do
        stub_command('virsh secret-list | grep 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8').and_return(true)
        stub_command('virsh secret-get-value 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8 | grep block_token')
          .and_return(true)
      end
      it { expect(chef_run).to_not create_template('/var/chef/cache/secret.xml') }
      it { expect(chef_run).to_not run_execute('virsh secret-define --file /var/chef/cache/secret.xml') }
      it { expect(chef_run).to_not run_execute('update virsh ceph secret') }
    end
  end

  context 'setting arch to ppc64le' do
    cached(:chef_run) { runner.converge(described_recipe) }
    before do
      node.automatic['kernel']['machine'] = 'ppc64le'
      stub_command('lscpu | grep "KVM"').and_return(false)
    end

    context 'Setting as openstack guest' do
      cached(:chef_run) { runner.converge(described_recipe) }
      before do
        stub_command('lscpu | grep "KVM"').and_return(true)
      end
      it { expect(chef_run).to load_kernel_module('kvm_pr') }
    end

    it { expect(chef_run).to load_kernel_module('kvm_hv') }

    %w(yum-kernel-osuosl::install base::grub).each do |r|
      it do
        expect(chef_run).to include_recipe(r)
      end
    end
    it { expect(chef_run).to_not load_kernel_module('kvm-intel') }
    it { expect(chef_run).to_not load_kernel_module('kvm-amd') }
    it do
      expect(chef_run).to render_file('/etc/default/grub').with_content(/^GRUB_CMDLINE_LINUX=.*kvm_cma_resv_ratio=15/)
    end
    it { expect(chef_run).to create_cookbook_file('/etc/rc.d/rc.local').with(mode: '644') }

    context 'POWER8' do
      cached(:chef_run) { runner.converge(described_recipe) }
      before do
        node.automatic['ibm_power']['cpu']['cpu_model'] = 'power8'
      end
      it { expect(chef_run).to enable_service('smt_off') }
      it { expect(chef_run).to start_service('smt_off') }
    end

    context 'POWER9' do
      cached(:chef_run) { runner.converge(described_recipe) }
      before do
        node.automatic['ibm_power']['cpu']['cpu_model'] = 'power9'
      end
      it { expect(chef_run).to_not enable_service('smt_off') }
      it { expect(chef_run).to_not start_service('smt_off') }
    end
  end

  context 'setting arch to aarch64' do
    cached(:chef_run) { runner.converge(described_recipe) }
    before do
      node.automatic['kernel']['machine'] = 'aarch64'
    end
    %w(yum-kernel-osuosl::install base::grub).each do |r|
      it { expect(chef_run).to include_recipe(r) }
    end
  end

  context 'setting arch to x86_64, processor to intel' do
    cached(:chef_run) { runner.converge(described_recipe) }
    before do
      node.automatic['kernel']['machine'] = 'x86_64'
      node.automatic['dmi']['processor']['manufacturer'] = 'Intel(R) Corporation'
    end
    it { expect(chef_run).to install_kernel_module('kvm-intel').with(options: %w(nested=1)) }
    it { expect(chef_run).to load_kernel_module('kvm-intel') }
    it { expect(chef_run).to_not load_kernel_module('kvm-amd') }
  end

  context 'setting arch to x86_64, processor to amd' do
    cached(:chef_run) { runner.converge(described_recipe) }
    before do
      node.automatic['kernel']['machine'] = 'x86_64'
      node.automatic['dmi']['processor']['manufacturer'] = 'AMD'
    end
    it { expect(chef_run).to install_kernel_module('kvm-amd').with(options: %w(nested=1)) }
    it { expect(chef_run).to load_kernel_module('kvm-amd') }
    it { expect(chef_run).to_not load_kernel_module('kvm-intel') }
  end
end
