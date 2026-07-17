require_relative '../../spec_helper'

describe 'osl-openstack::ops_messaging' do
  # EL10 is included here only — the messaging tier is the one piece
  # that runs on AlmaLinux 10 (RabbitMQ 4.2). Other suites stay EL8/9.
  [*ALL_PLATFORMS, ALMA_10].each do |pltfrm|
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

      it { is_expected.to accept_osl_firewall_port('amqp').with(osl_only: true) }
      it { is_expected.to accept_osl_firewall_port('rabbitmq_mgt').with(osl_only: true) }
      it { is_expected.to install_package 'rabbitmq-server' }
      %w(/etc/rabbitmq /var/lib/rabbitmq /var/log/rabbitmq).each do |dir|
        it { is_expected.to create_directory(dir).with(owner: 'rabbitmq', group: 'rabbitmq') }
      end

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
      %w(rabbitmq_management rabbitmq_prometheus).each do |plugin|
        it do
          is_expected.to run_execute("rabbitmq: enable plugin #{plugin}").with(
            command: "rabbitmq-plugins enable #{plugin}"
          )
        end
      end
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
      when ALMA_10
        it do
          is_expected.to create_yum_repository('centos-rabbitmq').with(
            description: 'CentOS $releasever - RabbitMQ',
            baseurl: 'https://centos-stream.osuosl.org/SIGs/$releasever-stream/messaging/$basearch/rabbitmq-4',
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

      it do
        is_expected.to run_execute('rabbitmq: set user tags openstack').with(
          command: 'rabbitmqctl set_user_tags openstack administrator'
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
          allow_any_instance_of(OSLOpenstack::Cookbook::Helpers).to receive(:openstack_rabbitmq_user_tag?).and_return(true)
        end

        it { is_expected.to nothing_execute('rabbitmq: add user openstack') }
        it { is_expected.to nothing_execute('rabbitmq: set permissions openstack') }
        it { is_expected.to nothing_execute('rabbitmq: set user tags openstack') }
      end

      context 'shared messaging tier (vhosts + TLS + CMR)' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.dup.merge(
            step_into: %w(osl_openstack_messaging)
          )).converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            openstack_secrets_stub.merge(
              'messaging' => openstack_secrets_stub['messaging'].merge(
                'tls' => true,
                'tls_only' => true,
                'cmr_target_group_size' => 3,
                'vhosts' => [{ 'vhost' => 'x86', 'user' => 'x86', 'pass' => 'x86pass' }]
              )
            )
          )
          allow_any_instance_of(OSLOpenstack::Cookbook::Helpers).to receive(:openstack_rabbitmq_vhost?).and_return(false)
          allow_any_instance_of(OSLOpenstack::Cookbook::Helpers).to receive(:openstack_rabbitmq_user?).and_return(false)
          allow_any_instance_of(OSLOpenstack::Cookbook::Helpers).to receive(:openstack_rabbitmq_permissions?).and_return(false)
        end

        it do
          is_expected.to create_certificate_manage('wildcard-rabbitmq').with(
            search_id: 'wildcard',
            cert_path: '/etc/rabbitmq/ssl',
            owner: 'rabbitmq',
            group: 'rabbitmq'
          )
        end

        it do
          is_expected.to run_execute('rabbitmq: add vhost x86').with(
            command: 'rabbitmqctl add_vhost x86'
          )
        end
        it do
          is_expected.to run_execute('rabbitmq: set permissions x86 on x86').with(
            command: 'rabbitmqctl set_permissions -p x86 x86 ".*" ".*" ".*"'
          )
        end

        it { is_expected.to render_file('/etc/rabbitmq/rabbitmq.conf').with_content('listeners.ssl.default = 5671') }
        it { is_expected.to render_file('/etc/rabbitmq/rabbitmq.conf').with_content('ssl_options.certfile = /etc/rabbitmq/ssl/certs/cert.pem') }
        it { is_expected.to render_file('/etc/rabbitmq/rabbitmq.conf').with_content(/^listeners.tcp = none$/) }
        it { is_expected.to render_file('/etc/rabbitmq/rabbitmq.conf').with_content('target_group_size = 3') }
      end

      context 'custom ssl_search_id' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.dup.merge(
            step_into: %w(osl_openstack_messaging)
          )).converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            openstack_secrets_stub.merge(
              'messaging' => openstack_secrets_stub['messaging'].merge(
                'tls' => true,
                'ssl_search_id' => 'wildcard-bak'
              )
            )
          )
        end

        it { is_expected.to create_certificate_manage('wildcard-rabbitmq').with(search_id: 'wildcard-bak') }
      end
    end
  end
end
