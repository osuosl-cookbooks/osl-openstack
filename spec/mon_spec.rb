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
        node.set['osl-openstack']['node_type'] = 'controller'
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
      expect(chef_run).to remove_package('nagios-plugins-openstack')
    end
    it do
      expect(chef_run.python_execute('monitoring-for-openstack deps')).to do_nothing
    end
    it do
      expect(chef_run.python_execute('monitoring-for-openstack install')).to do_nothing
    end
    it do
      expect(chef_run).to sync_git('/var/chef/cache/osops-tools-monitoring')
        .with(
          revision: '62160d10683023c8c9d96f616223d8def88b870d',
          repository: 'https://git.openstack.org/openstack/osops-tools-monitoring'
        )
    end
    it do
      expect(chef_run.git('/var/chef/cache/osops-tools-monitoring')).to \
        notify('python_execute[monitoring-for-openstack deps]').immediately
    end
    it do
      expect(chef_run.git('/var/chef/cache/osops-tools-monitoring')).to \
        notify('python_execute[monitoring-for-openstack install]').immediately
    end
    it do
      expect(chef_run).to create_file(check_openstack)
    end
    it do
      expect(chef_run).to install_sudo('nrpe-openstack')
        .with(
          user: '%nrpe',
          nopasswd: true,
          runas: 'root',
          commands: [check_openstack]
        )
    end
    %w(
      check_nova_services
      check_nova_hypervisors
      check_nova_images
      check_neutron_agents
      check_cinder_services
    ).each do |check|
      it do
        expect(chef_run).to remove_nrpe_check(check)
      end
    end

    %w(
      check_cinder_api
      check_glance_api
      check_keystone_api
      check_neutron_api
      check_neutron_floating_ip
      check_nova_api
    ).each do |check|
      it do
        expect(chef_run.link(::File.join(plugin_dir, check))).to \
          link_to("/usr/libexec/openstack-monitoring/checks/oschecks-#{check}")
      end
      it do
        expect(chef_run).to add_nrpe_check(check).with(command: "/bin/sudo #{check_openstack} #{check}")
      end
    end
  end
end
