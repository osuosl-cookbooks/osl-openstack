require_relative '../../spec_helper'

describe 'osl-openstack::mon' do
  # EL10: the shared messaging tier is the only thing running there.
  [*ALL_PLATFORMS, ALMA_10].each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
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
      context 'HA controller' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.normal['osl-openstack']['node_type'] = 'controller'
            node.automatic['fqdn'] = 'controller1.testing.osuosl.org'
          end.converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            'database_server' => { 'suffix' => 'x86' },
            'ha' => {
              'api_listen_ip' => {
                'controller1.testing.osuosl.org' => '10.1.2.3',
              },
            }
          )
        end

        # Each nrpe_check should target the per-host backend IP from
        # ha.api_listen_ip, not node['ipaddress']. In HA the keystone
        # and novnc backends serve plain HTTP / ws (haproxy on the VIP
        # is the TLS endpoint), so the local check drops --ssl - check
        # the actual backend, not what the public endpoint speaks.
        {
          'check_keystone_api' => '-I 10.1.2.3 -p 5000',
          'check_glance_api' => '-I 10.1.2.3 -p 9292',
          'check_nova_api' => '-I 10.1.2.3 -p 8774',
          'check_nova_placement_api' => '-I 10.1.2.3 -p 8778',
          'check_novnc' => '-I 10.1.2.3 -p 6080',
          'check_neutron_api' => '-I 10.1.2.3 -p 9696',
          'check_cinder_api' => '-I 10.1.2.3 -p 8776',
          'check_heat_api' => '-I 10.1.2.3 -p 8004',
        }.each do |name, params|
          it "passes the api_listen_ip to #{name}" do
            expect(chef_run).to add_nrpe_check(name).with(parameters: params)
          end
        end
      end

      context 'messaging' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.normal['osl-openstack']['node_type'] = 'messaging'
          end.converge(described_recipe)
        end

        it { is_expected.to_not install_package 'nagios-plugins-http' }
        it { is_expected.to install_package 'python3' }

        %w(nagios nrpe).each do |u|
          it do
            is_expected.to create_sudo("check_rabbitmq-#{u}").with(
              user: [u],
              runas: 'root',
              nopasswd: true,
              commands: %w(/usr/sbin/rabbitmq-diagnostics /usr/sbin/rabbitmqctl)
            )
          end
        end

        it { is_expected.to create_cookbook_file('/usr/lib64/nagios/plugins/check_rabbitmq_cluster').with(mode: '755') }

        it do
          is_expected.to add_nrpe_check('check_rabbitmq_running').with(
            command: 'sudo /usr/sbin/rabbitmq-diagnostics',
            parameters: '-q check_running'
          )
        end
        it do
          is_expected.to add_nrpe_check('check_rabbitmq_alarms').with(
            command: 'sudo /usr/sbin/rabbitmq-diagnostics',
            parameters: '-q check_alarms'
          )
        end
        it do
          is_expected.to add_nrpe_check('check_rabbitmq_cluster').with(
            command: '/usr/lib64/nagios/plugins/check_rabbitmq_cluster',
            parameters: '3'
          )
        end
        it do
          is_expected.to add_nrpe_check('check_rabbitmq_listener').with(
            command: 'sudo /usr/sbin/rabbitmq-diagnostics',
            parameters: '-q check_port_listener 5672'
          )
        end

        context 'TLS tier' do
          cached(:chef_run) do
            ChefSpec::SoloRunner.new(pltfrm) do |node|
              node.normal['osl-openstack']['node_type'] = 'messaging'
            end.converge(described_recipe)
          end

          before do
            stub_data_bag_item('openstack', 'x86').and_return(
              openstack_secrets_stub.merge(
                'messaging' => openstack_secrets_stub['messaging'].merge(
                  'tls' => true,
                  'cmr_target_group_size' => 3
                )
              )
            )
          end

          it { is_expected.to add_nrpe_check('check_rabbitmq_listener').with(parameters: '-q check_port_listener 5671') }
          it { is_expected.to add_nrpe_check('check_rabbitmq_cluster').with(parameters: '3') }
        end
      end

      context 'ppc64le' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
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
