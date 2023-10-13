require_relative 'spec_helper'

describe 'osl-openstack::mon' do
  cached(:chef_run) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS).converge(described_recipe)
  end
  it 'converges successfully' do
    expect { chef_run }.to_not raise_error
  end
  it do
    expect(chef_run).to include_recipe('osl-nrpe::default')
  end
  context 'Setting arch to ppc64le' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.automatic['kernel']['machine'] = 'ppc64le'
      end.converge('osl-nrpe', described_recipe)
    end
    it do
      total_cpu = chef_run.node['cpu']['total']
      expect(chef_run).to add_nrpe_check('check_load').with(
        warning_condition: "#{total_cpu * 5 + 10},#{total_cpu * 5 + 5},#{total_cpu * 5}",
        critical_condition: "#{total_cpu * 8 + 10},#{total_cpu * 8 + 5},#{total_cpu * 8}"
      )
    end
  end
  context 'controller node' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.override['osl-openstack']['node_type'] = 'controller'
        node.automatic['filesystem2']['by_mountpoint']
      end.converge(described_recipe)
    end
    include_context 'identity_stubs'

    it { expect(chef_run).to install_package('nagios-plugins-http') }
    it do
      expect(chef_run).to add_nrpe_check('check_keystone_api')
        .with(
          command: '/usr/lib64/nagios/plugins/check_http',
          parameters: '--ssl -I 10.0.0.2 -p 5000'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_glance_api')
        .with(
          command: '/usr/lib64/nagios/plugins/check_http',
          parameters: '-I 10.0.0.2 -p 9292'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_nova_api')
        .with(
          command: '/usr/lib64/nagios/plugins/check_http',
          parameters: '-I 10.0.0.2 -p 8774'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_nova_placement_api')
        .with(
          command: '/usr/lib64/nagios/plugins/check_http',
          parameters: '-I 10.0.0.2 -p 8778'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_novnc')
        .with(
          command: '/usr/lib64/nagios/plugins/check_http',
          parameters: '--ssl -I 10.0.0.2 -p 6080'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_neutron_api')
        .with(
          command: '/usr/lib64/nagios/plugins/check_http',
          parameters: '-I 10.0.0.2 -p 9696'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_cinder_api')
        .with(
          command: '/usr/lib64/nagios/plugins/check_http',
          parameters: '-I 10.0.0.2 -p 8776'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_heat_api')
        .with(
          command: '/usr/lib64/nagios/plugins/check_http',
          parameters: '-I 10.0.0.2 -p 8004'
        )
    end
    it do
      expect(chef_run).to_not create_file('/usr/local/etc/os_cluster')
    end
    it do
      expect(chef_run).to_not install_chef_gem('prometheus_reporter')
    end
    it do
      expect(chef_run).to_not create_cookbook_file('/usr/local/libexec/openstack-prometheus')
    end
    it do
      expect(chef_run).to_not create_cookbook_file('/usr/local/libexec/openstack-prometheus.rb')
    end
    it do
      expect(chef_run).to_not create_cron('openstack-prometheus')
    end
    context 'cluster_name set' do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
          node.override['osl-openstack']['cluster_name'] = 'x86'
          node.override['osl-openstack']['node_type'] = 'controller'
        end.converge(described_recipe)
      end
      it do
        expect(chef_run).to create_file('/usr/local/etc/os_cluster').with(content: "export OS_CLUSTER=x86\n")
      end
      it do
        expect(chef_run).to install_chef_gem('prometheus_reporter')
      end
      it do
        expect(chef_run).to create_cookbook_file('/usr/local/libexec/openstack-prometheus').with(mode: '755')
      end
      it do
        expect(chef_run).to create_cookbook_file('/usr/local/libexec/openstack-prometheus.rb').with(mode: '755')
      end
      it do
        expect(chef_run).to create_cron('openstack-prometheus').with(
          command: '/usr/local/libexec/openstack-prometheus',
          minute: '*/10'
        )
      end
    end
  end
end
