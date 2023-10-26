require_relative '../../spec_helper'

describe 'osl-openstack::mon' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm) do |node|
          node.normal['osl-openstack']['cluster_name'] = 'x86'
        end.converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to include_recipe 'osl-nrpe' }
      it { is_expected.to_not install_package 'nagios-plugins-http' }

      it do
        is_expected.to add_nrpe_check('check_load').with(
          warning_condition: '12,7,2',
          critical_condition: '14,9,4'
        )
      end

      context 'controller' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.normal['osl-openstack']['cluster_name'] = 'x86'
            node.normal['osl-openstack']['node_type'] = 'controller'
          end.converge(described_recipe)
        end

        it { is_expected.to install_package 'nagios-plugins-http' }
        it do
          is_expected.to add_nrpe_check('check_keystone_api').with(
            command: '/usr/lib64/nagios/plugins/check_http',
            parameters: '--ssl -I 10.0.0.2 -p 5000'
          )
        end
        it do
          is_expected.to add_nrpe_check('check_glance_api').with(
            command: '/usr/lib64/nagios/plugins/check_http',
            parameters: '-I 10.0.0.2 -p 9292'
          )
        end
        it do
          is_expected.to add_nrpe_check('check_nova_api').with(
            command: '/usr/lib64/nagios/plugins/check_http',
            parameters: '-I 10.0.0.2 -p 8774'
          )
        end
        it do
          is_expected.to add_nrpe_check('check_nova_placement_api').with(
            command: '/usr/lib64/nagios/plugins/check_http',
            parameters: '-I 10.0.0.2 -p 8778'
          )
        end
        it do
          is_expected.to add_nrpe_check('check_novnc').with(
            command: '/usr/lib64/nagios/plugins/check_http',
            parameters: '--ssl -I 10.0.0.2 -p 6080'
          )
        end
        it do
          is_expected.to add_nrpe_check('check_neutron_api').with(
            command: '/usr/lib64/nagios/plugins/check_http',
            parameters: '-I 10.0.0.2 -p 9696'
          )
        end
        it do
          is_expected.to add_nrpe_check('check_cinder_api').with(
            command: '/usr/lib64/nagios/plugins/check_http',
            parameters: '-I 10.0.0.2 -p 8776'
          )
        end
        it do
          is_expected.to add_nrpe_check('check_heat_api').with(
            command: '/usr/lib64/nagios/plugins/check_http',
            parameters: '-I 10.0.0.2 -p 8004'
          )
        end
        it do
          is_expected.to create_file('/usr/local/etc/os_cluster').with(
            content: "export OS_CLUSTER=x86\n"
          )
        end
        it do
          is_expected.to install_chef_gem('prometheus_reporter').with(
            source: 'https://packagecloud.io/osuosl/prometheus_reporter'
          )
        end
        it { is_expected.to create_cookbook_file('/usr/local/libexec/openstack-prometheus').with(mode: '755') }
        it { is_expected.to create_cookbook_file('/usr/local/libexec/openstack-prometheus.rb').with(mode: '755') }
        it do
          is_expected.to create_cron('openstack-prometheus').with(
            command: '/usr/local/libexec/openstack-prometheus',
            minute: '*/10'
          )
        end
      end
      context 'ppc64le' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.normal['osl-openstack']['cluster_name'] = 'x86'
            node.automatic['kernel']['machine'] = 'ppc64le'
          end.converge(described_recipe)
        end

        it do
          is_expected.to add_nrpe_check('check_load').with(
            warning_condition: '15,10,5',
            critical_condition: '18,13,8'
          )
        end
      end
    end
  end
end
