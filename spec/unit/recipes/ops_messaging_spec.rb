require_relative '../../spec_helper'

describe 'osl-openstack::ops_messaging' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm.dup.merge(
          step_into: %w(osl_openstack_messaging)
        )).converge(described_recipe)
      end

      include_context 'common_stubs'

      it do
        is_expected.to create_osl_openstack_messaging('default').with(
          user: 'openstack',
          pass: 'openstack'
        )
      end

      it { is_expected.to add_osl_repos_openstack 'default' }
      it { is_expected.to accept_osl_firewall_port('amqp').with(osl_only: true) }
      it { is_expected.to accept_osl_firewall_port('rabbitmq_mgt').with(osl_only: true) }
      it { is_expected.to install_package 'rabbitmq-server' }

      it do
        is_expected.to create_osl_systemd_unit_drop_in('ulimit').with(
          content: {
            'Service' => {
              'LimitNOFILE' => 300000,
            },
          },
          unit_name: 'rabbitmq-server.service'
        )
      end

      it { is_expected.to enable_service 'rabbitmq-server' }
      it { is_expected.to start_service 'rabbitmq-server' }
      case pltfrm
      when ALMA_8
        it do
          is_expected.to create_yum_repository('centos-rabbitmq').with(
            description: 'CentOS $releasever - RabbitMQ',
            baseurl: 'https://ftp.osuosl.org/pub/osl/vault/$releasever-stream/messaging/$basearch/rabbitmq-38',
            gpgkey: 'https://www.centos.org/keys/RPM-GPG-KEY-CentOS-SIG-Messaging',
            priority: '20'
          )
        end
      when ALMA_9
        it do
          is_expected.to create_yum_repository('centos-rabbitmq').with(
            description: 'CentOS $releasever - RabbitMQ',
            baseurl: 'https://centos-stream.osuosl.org/SIGs/$releasever-stream/messaging/$basearch/rabbitmq-38',
            gpgkey: 'https://www.centos.org/keys/RPM-GPG-KEY-CentOS-SIG-Messaging',
            priority: '20'
          )
        end
      end

      it do
        is_expected.to run_execute('rabbitmq: add user openstack').with(
          command: 'rabbitmqctl add_user openstack openstack',
          sensitive: true
        )
      end

      it do
        is_expected.to run_execute('rabbitmq: set permissions openstack').with(
          command: 'rabbitmqctl set_permissions openstack ".*" ".*" ".*"',
          sensitive: true
        )
      end

      context 'user created' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.dup.merge(
            step_into: %w(osl_openstack_messaging)
          )).converge(described_recipe)
        end

        before do
          allow_any_instance_of(OSLOpenstack::Cookbook::Helpers).to receive(:openstack_rabbitmq_user?).and_return(true)
          allow_any_instance_of(OSLOpenstack::Cookbook::Helpers).to receive(:openstack_rabbitmq_permissions?).and_return(true)
        end

        it { is_expected.to nothing_execute('rabbitmq: add user openstack') }
        it { is_expected.to nothing_execute('rabbitmq: set permissions openstack') }
      end
    end
  end
end
