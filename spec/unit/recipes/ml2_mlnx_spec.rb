require_relative '../../spec_helper'

describe 'osl-openstack::ml2_mlnx' do
  cached(:chef_run) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS).converge(described_recipe)
  end
  include_context 'identity_stubs'
  include_context 'network_stubs'
  include_context 'mellanox_stubs'
  it 'converges successfully' do
    expect { chef_run }.to_not raise_error
  end
  %w(
    osl-openstack
    openstack-network
    base::oslrepo
    openstack-network::plugin_config
  ).each do |r|
    it do
      expect(chef_run).to include_recipe(r)
    end
  end
  it do
    expect(chef_run).to create_yum_repository('mellanox-ofed')
      .with(
        description: 'Mellanox OFED',
        gpgkey: 'http://packages.osuosl.org/repositories/centos-$releasever/mellanox-ofed/RPM-GPG-KEY-Mellanox',
        url: 'http://packages.osuosl.org/repositories/centos-$releasever/mellanox-ofed/$basearch'
      )
  end
  %w(mlnx-ofed-hypervisor mlnx-fw-updater libvirt-python python-ethtool python-networking-mlnx).each do |p|
    it do
      expect(chef_run).to install_package(p)
    end
  end
  it do
    expect(chef_run).to load_kernel_module('mlx4_core')
      .with(
        onboot: true,
        reload: false,
        options: %w(port_type_array=2 num_vfs=8 probe_vf=8 log_num_mgm_entry_size=-1 debug_level=1)
      )
  end
  it do
    expect(chef_run.kernel_module('mlx4_core')).to notify('service[openibd]').to(:restart)
  end
  it do
    expect(chef_run).to enable_service('openibd')
  end
  it do
    expect(chef_run).to start_service('openibd')
  end
  it do
    expect(chef_run).to start_service('neutron-plugin-mlnx-agent')
      .with(
        service_name: 'neutron-mlnx-agent',
        supports: { status: true, restart: true }
      )
  end
  it do
    expect(chef_run).to enable_service('neutron-plugin-mlnx-agent')
  end
  [
    'template[/etc/neutron/neutron.conf]',
    'template[/etc/neutron/plugins/mlnx/mlnx_conf.ini]'
  ].each do |t|
    it do
      expect(chef_run.service('neutron-plugin-mlnx-agent')).to subscribe_to(t)
    end
  end
  it do
    expect(chef_run).to start_service('neutron-eswitchd')
      .with(
        service_name: 'eswitchd',
        supports: { status: true, restart: true }
      )
  end
  it do
    expect(chef_run).to enable_service('neutron-eswitchd')
  end
  [
    'template[/etc/neutron/neutron.conf]',
    'template[/etc/neutron/plugins/ml2/eswitchd.conf]'
  ].each do |t|
    it do
      expect(chef_run.service('neutron-eswitchd')).to subscribe_to(t)
    end
  end
  context '/etc/neutron/plugins/mlnx/mlnx_conf.ini' do
    let(:file) { chef_run.template('/etc/neutron/plugins/mlnx/mlnx_conf.ini') }
    [
      %r{^daemon_endpoint = tcp://127.0.0.1:60001$},
      /^request_timeout = 3000$/,
      /^retries = 3$/,
      /^backoff_rate = 2$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('eswitch', line)
      end
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content('agent', /^polling_interval = 2$/)
    end
  end
  context '/etc/neutron/plugins/ml2/eswitchd.conf' do
    let(:file) { chef_run.template('/etc/neutron/plugins/ml2/eswitchd.conf') }
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content('DAEMON', /^fabrics = default:autoeth$/)
    end
  end
end
