require_relative '../../spec_helper'

describe 'osl-openstack::ops_messaging' do
  # The Messaging SIG repo is the only platform difference, so only the
  # default converge runs on EL9 as well as EL10 where the tier lives
  rabbitmq_subdir = { ALMA_9 => 'rabbitmq-38', ALMA_10 => 'rabbitmq-4' }

  [*ALL_PLATFORMS, ALMA_10].each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm.merge(
          step_into: %w(osl_openstack_messaging)
        )).converge(described_recipe)
      end

      include_context 'common_stubs'
      include_context 'rabbitmq_stubs'

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
      it do
        is_expected.to manage_selinux_port('15692 tcp').with(
          port: '15692',
          protocol: 'tcp',
          secontext: 'amqp_port_t'
        )
      end
      it do
        is_expected.to create_yum_repository('centos-rabbitmq').with(
          description: 'CentOS $releasever - RabbitMQ',
          baseurl: "https://centos-stream.osuosl.org/SIGs/$releasever-stream/messaging/$basearch/#{rabbitmq_subdir[pltfrm]}",
          gpgkey: 'https://www.centos.org/keys/RPM-GPG-KEY-CentOS-SIG-Messaging',
          priority: '20'
        )
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
    end
  end

  context 'without the prometheus plugin' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(ALMA_9.merge(
        step_into: %w(osl_openstack_messaging)
      )).converge(described_recipe)
    end

    include_context 'common_stubs'
    include_context 'rabbitmq_stubs'

    before do
      stub_data_bag_item('openstack', 'x86').and_return(
        openstack_secrets_stub('messaging' => { 'plugins' => %w(rabbitmq_management) })
      )
    end

    it { is_expected.to run_execute('rabbitmq: enable plugin rabbitmq_management') }
    it { is_expected.to_not run_execute('rabbitmq: enable plugin rabbitmq_prometheus') }
    it { is_expected.to_not manage_selinux_port('15692 tcp') }
  end

  context 'almalinux 10 shared messaging tier' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(ALMA_10.merge(
        step_into: %w(osl_openstack_messaging)
      )).converge(described_recipe)
    end

    include_context 'common_stubs'
    include_context 'rabbitmq_stubs'

    # The openstack user already exists; the per-cloud x86 vhost and user don't
    before do
      stub_data_bag_item('openstack', 'x86').and_return(
        openstack_secrets_stub(
          'messaging' => {
            'tls' => true,
            'tls_only' => true,
            'ssl_search_id' => 'wildcard-bak',
            'cmr_target_group_size' => 5,
            'vhosts' => [{ 'vhost' => 'x86', 'user' => 'x86', 'pass' => 'x86pass' }],
          }
        )
      )
      helpers = OSLOpenstack::Cookbook::Helpers
      allow_any_instance_of(helpers).to receive(:openstack_rabbitmq_user?) { |_, user| user == 'openstack' }
      allow_any_instance_of(helpers).to receive(:openstack_rabbitmq_permissions?) { |_, _user, vhost| vhost.nil? }
      allow_any_instance_of(helpers).to receive(:openstack_rabbitmq_user_tag?).and_return(true)
      allow_any_instance_of(helpers).to receive(:openstack_rabbitmq_vhost?).and_return(false)
      allow_any_instance_of(helpers).to receive(:openstack_rabbitmq_policy?).and_return(false)
    end

    it { is_expected.to nothing_execute('rabbitmq: add user openstack') }
    it { is_expected.to nothing_execute('rabbitmq: set permissions openstack') }
    it { is_expected.to nothing_execute('rabbitmq: set user tags openstack') }

    it do
      is_expected.to create_certificate_manage('wildcard-rabbitmq').with(
        search_id: 'wildcard-bak',
        cert_path: '/etc/rabbitmq/ssl',
        owner: 'rabbitmq',
        group: 'rabbitmq'
      )
    end

    it { is_expected.to run_execute('rabbitmq: add vhost x86').with(command: 'rabbitmqctl add_vhost x86') }
    it { is_expected.to run_execute('rabbitmq: add user x86') }
    it do
      is_expected.to run_execute('rabbitmq: set permissions x86 on x86').with(
        command: 'rabbitmqctl set_permissions -p x86 x86 ".*" ".*" ".*"'
      )
    end
    it do
      is_expected.to run_execute('rabbitmq: set policy stale-heat-queues on x86').with(
        command: 'rabbitmqctl set_policy -p x86 stale-heat-queues ' \
                 '\'^(heat-engine-listener|engine_worker)\\.\' \'{"expires":3600000}\' --apply-to queues'
      )
    end

    it { is_expected.to render_file('/etc/rabbitmq/rabbitmq.conf').with_content('listeners.ssl.default = 5671') }
    it { is_expected.to render_file('/etc/rabbitmq/rabbitmq.conf').with_content('ssl_options.certfile = /etc/rabbitmq/ssl/certs/cert.pem') }
    it { is_expected.to render_file('/etc/rabbitmq/rabbitmq.conf').with_content(/^listeners.tcp = none$/) }
    it { is_expected.to render_file('/etc/rabbitmq/rabbitmq.conf').with_content('target_group_size = 5') }
  end
end
