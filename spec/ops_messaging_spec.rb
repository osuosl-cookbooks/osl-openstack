require_relative 'spec_helper'

describe 'osl-openstack::ops_messaging' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm.dup.merge(step_into: %w(osl_openstack_messaging))) do |node|
          node.normal['osl-openstack']['cluster_name'] = 'x86'
        end.converge(described_recipe)
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
      it { is_expected.to enable_service 'rabbitmq-server' }
      it { is_expected.to start_service 'rabbitmq-server' }

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
          ChefSpec::SoloRunner.new(pltfrm.dup.merge(step_into: %w(osl_openstack_messaging))) do |node|
            node.normal['osl-openstack']['cluster_name'] = 'x86'
          end.converge(described_recipe)
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
