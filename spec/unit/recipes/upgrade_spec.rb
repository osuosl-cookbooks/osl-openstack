require_relative '../../spec_helper'

describe 'osl-openstack::upgrade' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to install_package 'crudini' }
      it { is_expected.to stop_service 'yum-cron' }
      it { is_expected.to disable_service 'yum-cron' }
      it { is_expected.to stop_service 'dnf-automatic.timer' }
      it { is_expected.to disable_service 'dnf-automatic.timer' }
      it { is_expected.to add_osl_repos_openstack 'upgrade' }
      it { is_expected.to accept_osl_firewall_openstack 'upgrade' }
      it { is_expected.to_not accept_osl_firewall_memcached 'upgrade' }
      it { is_expected.to_not accept_osl_firewall_port 'amqp' }
      it { is_expected.to_not accept_osl_firewall_port 'rabbitmq_mgt' }
      it { is_expected.to_not accept_osl_firewall_port 'http' }
      it { is_expected.to_not create_file '/root/nova-cell-db-uri' }
      it do
        is_expected.to create_cookbook_file('/root/upgrade.sh').with(
          source: 'upgrade-compute.sh',
          mode: '755'
        )
      end
      it { is_expected.to run_ruby_block 'raise_upgrade_exeception' }

      context 'controller' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.normal['osl-openstack']['node_type'] = 'controller'
          end.converge(described_recipe)
        end
        it { is_expected.to accept_osl_firewall_memcached 'upgrade' }
        it { is_expected.to accept_osl_firewall_port('amqp').with(osl_only: true) }
        it { is_expected.to accept_osl_firewall_port('rabbitmq_mgt').with(osl_only: true) }
        it { is_expected.to accept_osl_firewall_port('http').with(ports: %w(80 443)) }
        it do
          is_expected.to create_cookbook_file('/root/upgrade.sh').with(
            source: 'upgrade-controller.sh',
            mode: '755'
          )
        end
      end

      context '/root/ussuri-upgrade-done' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
        end
        before do
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with('/root/ussuri-upgrade-done').and_return(true)
        end
        it { is_expected.to_not run_ruby_block 'raise_upgrade_exeception' }
        it { is_expected.to_not stop_service 'yum-cron' }
        it { is_expected.to_not disable_service 'yum-cron' }
        it { is_expected.to_not stop_service 'dnf-automatic.timer' }
        it { is_expected.to_not disable_service 'dnf-automatic.timer' }
      end
    end
  end
end
