require_relative 'spec_helper'

describe 'osl-openstack::mon' do
  cached(:chef_run) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS).converge(described_recipe)
  end
  it 'converges successfully' do
    expect { chef_run }.to_not raise_error
  end
  %w(osl-nrpe::default osl-munin::client).each do |r|
    it do
      expect(chef_run).to include_recipe(r)
    end
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
  it do
    expect(chef_run).to_not create_munin_plugin('cma')
  end
  context 'compute node w/ 4.14 kernel' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.override['osl-openstack']['node_type'] = 'compute'
        node.automatic['kernel']['release'] = '4.14.23-gentoo-osuosl-1.x86_64'
        node.automatic['filesystem2']['by_mountpoint']
      end.converge(described_recipe)
    end
    include_context 'identity_stubs'
    it do
      expect(chef_run).to create_munin_plugin('cma').with(plugin_dir: '/usr/share/munin/contrib/plugins/osuosl')
    end
  end
  context 'controller node' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS.dup.merge(step_into: %w(osc_nagios_check))) do |node|
        node.override['osl-openstack']['node_type'] = 'controller'
        node.automatic['filesystem2']['by_mountpoint']
      end.converge(described_recipe)
    end
    include_context 'identity_stubs'
    plugin_dir = '/usr/lib64/nagios/plugins'
    check_openstack = ::File.join(plugin_dir, 'check_openstack')
    %w(osl-openstack base::oslrepo).each do |r|
      it do
        expect(chef_run).to include_recipe(r)
      end
    end
    it do
      expect(chef_run).to run_execute('virtualenv /opt/osc-nagios')
        .with(
          creates: '/opt/osc-nagios/bin/pip'
        )
    end
    it do
      expect(chef_run).to remove_package('nagios-plugins-openstack')
    end
    it do
      expect(chef_run).to nothing_execute('monitoring-for-openstack deps').with(
        command: '/opt/osc-nagios/bin/pip install -r requirements.txt',
        cwd: '/var/chef/cache/osops-tools-monitoring/monitoring-for-openstack'
      )
    end
    it do
      expect(chef_run).to nothing_execute('monitoring-for-openstack install').with(
        command: '/opt/osc-nagios/bin/python setup.py install',
        cwd: '/var/chef/cache/osops-tools-monitoring/monitoring-for-openstack'
      )
    end
    it do
      expect(chef_run).to sync_git('/var/chef/cache/osops-tools-monitoring')
        .with(
          revision: 'rocky',
          repository: 'https://github.com/osuosl/osops-tools-monitoring.git'
        )
    end
    it do
      expect(chef_run.git('/var/chef/cache/osops-tools-monitoring')).to \
        notify('execute[monitoring-for-openstack deps]').immediately
    end
    it do
      expect(chef_run.git('/var/chef/cache/osops-tools-monitoring')).to \
        notify('execute[monitoring-for-openstack install]').immediately
    end
    it do
      expect(chef_run).to create_file(check_openstack)
    end
    it do
      expect(chef_run).to create_sudo('nrpe-openstack')
        .with(
          user: ['%nrpe'],
          nopasswd: true,
          runas: 'root',
          commands: [check_openstack]
        )
    end
    %w(
      check_cinder_api
      check_cinder_services
      check_neutron_agents
      check_neutron_floating_ip
      check_nova_hypervisors
      check_nova_images
      check_nova_services
    ).each do |check|
      it do
        expect(chef_run).to remove_nrpe_check(check)
      end
    end

    %w(
      check_glance_api
      check_keystone_api
      check_neutron_api
    ).each do |check|
      it do
        expect(chef_run).to add_osc_nagios_check(check)
      end
      it do
        expect(chef_run.link(::File.join(plugin_dir, check))).to \
          link_to("/usr/libexec/openstack-monitoring/checks/oschecks-#{check}")
      end
      it do
        expect(chef_run).to add_nrpe_check(check).with(command: "/bin/sudo #{check_openstack} #{check}")
      end
    end
    it do
      expect(chef_run).to add_osc_nagios_check('check_nova_api').with(parameters: '--os-compute-api-version 2')
    end
    it do
      expect(chef_run.link(::File.join(plugin_dir, 'check_nova_api'))).to \
        link_to('/usr/libexec/openstack-monitoring/checks/oschecks-check_nova_api')
    end
    it do
      expect(chef_run).to add_nrpe_check('check_nova_api')
        .with(
          command: "/bin/sudo #{check_openstack} check_nova_api",
          parameters: '--os-compute-api-version 2'
        )
    end
    it do
      expect(chef_run).to add_osc_nagios_check('check_cinder_api_v2')
        .with(
          plugin: 'check_cinder_api',
          parameters: '--os-volume-api-version 2'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_cinder_api_v2')
        .with(
          command: "/bin/sudo #{check_openstack} check_cinder_api",
          parameters: '--os-volume-api-version 2'
        )
    end
    it do
      expect(chef_run.link(::File.join(plugin_dir, 'check_cinder_api'))).to \
        link_to('/usr/libexec/openstack-monitoring/checks/oschecks-check_cinder_api')
    end
    it do
      expect(chef_run).to add_osc_nagios_check('check_cinder_api_v3')
        .with(
          plugin: 'check_cinder_api',
          parameters: '--os-volume-api-version 3'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_cinder_api_v3')
        .with(
          command: "/bin/sudo #{check_openstack} check_cinder_api",
          parameters: '--os-volume-api-version 3'
        )
    end
    it do
      expect(chef_run).to add_osc_nagios_check('check_neutron_floating_ip_public')
        .with(
          plugin: 'check_neutron_floating_ip',
          parameters: '--ext_network_name public'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_neutron_floating_ip_public')
        .with(
          command: "/bin/sudo #{check_openstack} check_neutron_floating_ip",
          parameters: '--ext_network_name public'
        )
    end
    it do
      expect(chef_run.link(::File.join(plugin_dir, 'check_neutron_floating_ip'))).to \
        link_to('/usr/libexec/openstack-monitoring/checks/oschecks-check_neutron_floating_ip')
    end
    it do
      expect(chef_run).to_not create_file('/usr/local/etc/os_cluster')
    end
    it do
      expect(chef_run).to_not create_cookbook_file('/usr/local/libexec/openstack-prometheus')
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
        expect(chef_run).to create_file('/usr/local/etc/os_cluster').with(content: "x86\n")
      end
      it do
        expect(chef_run).to create_cookbook_file('/usr/local/libexec/openstack-prometheus').with(mode: '755')
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
