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
        end.converge('osl-nrpe', described_recipe)
      end
      it do
        total_cpu = chef_run.node['cpu']['total']
        expect(chef_run).to add_nrpe_check('check_load').with(
          warning_condition: "#{total_cpu * 4 + 10},#{total_cpu * 4 + 5},#{total_cpu * 4}",
          critical_condition: "#{total_cpu * 8 + 10},#{total_cpu * 8 + 5},#{total_cpu * 8}"
        )
      end
    end
  end
  context 'controller node' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.set['osl-openstack']['node_type'] = 'controller'
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
      expect(chef_run).to install_package('nagios-plugins-openstack')
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
    it do
      expect(chef_run).to add_nrpe_check('check_nova_services')
        .with(
          command: '/bin/sudo ' + check_openstack + ' check_nova-services',
          warning_condition: '5:',
          critical_condition: '4:'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_nova_hypervisors')
        .with(
          command: '/bin/sudo ' + check_openstack + ' check_nova-hypervisors',
          parameters: '--warn_memory_percent 0:80' \
                      ' --critical_memory_percent 0:90' \
                      ' --warn_vcpus_percent 0:80' \
                      ' --critical_vcpus_percent 0:90'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_nova_images')
        .with(
          command: '/bin/sudo ' + check_openstack + ' check_nova-images',
          warning_condition: 1,
          critical_condition: 2
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_neutron_agents')
        .with(
          command: '/bin/sudo ' + check_openstack + ' check_neutron-agents',
          warning_condition: '5:',
          critical_condition: '4:'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_cinder_services')
        .with(
          command: '/bin/sudo ' + check_openstack + ' check_cinder-services',
          warning_condition: '2:',
          critical_condition: '1:'
        )
    end
    it do
      expect(chef_run).to add_nrpe_check('check_keystone_token')
        .with(
          command: '/bin/sudo ' + check_openstack + ' check_keystone-token'
        )
    end
  end
end
