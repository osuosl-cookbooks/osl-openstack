require_relative '../../spec_helper'

describe 'osl-openstack::telemetry_controller' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'
      include_context 'telemetry_stubs'

      it { is_expected.to add_osl_repos_openstack 'telemetry-controller' }
      it { is_expected.to create_osl_openstack_client 'telemetry-controller' }
      it { is_expected.to accept_osl_firewall_openstack 'telemetry-controller' }
      it do
        is_expected.to create_osl_openstack_user('ceilometer').with(
          domain_name: 'default',
          role_name: 'admin',
          project_name: 'service',
          password: 'ceilometer'
        )
      end
      it { is_expected.to grant_role_osl_openstack_user 'ceilometer' }
      it do
        is_expected.to install_package(
          %w(
            openstack-ceilometer-central
            openstack-ceilometer-notification
          )
        )
      end
      it { is_expected.to include_recipe 'osl-openstack::telemetry_common' }
      it { is_expected.to install_package 'openstack-ceilometer-common' }
      it do
        is_expected.to create_template('/etc/ceilometer/ceilometer.conf').with(
          owner: 'root',
          group: 'ceilometer',
          mode: '0640',
          sensitive: true,
          variables: {
              auth_endpoint: 'controller.example.com',
              memcached_endpoint: 'controller.example.com:11211',
              service_pass: 'ceilometer',
              transport_url: 'rabbit://openstack:openstack@controller.example.com:5672',
          }
        )
      end
      it do
        is_expected.to create_template('/etc/ceilometer/pipeline.yaml').with(
          owner: 'ceilometer',
          group: 'ceilometer',
          mode: '0640',
          variables: {
              publishers: %w(prometheus://localhost:9091/metrics/job/ceilometer),
          }
        )
      end
      it do
        expect(chef_run.template('/etc/ceilometer/pipeline.yaml')).to \
          notify('service[openstack-ceilometer-notification]').to(:restart)
      end
      it do
        expect(chef_run.template('/etc/ceilometer/pipeline.yaml')).to \
          notify('service[openstack-ceilometer-central]').to(:restart)
      end
      it { is_expected.to enable_service 'openstack-ceilometer-central' }
      it { is_expected.to start_service 'openstack-ceilometer-central' }
      it { is_expected.to enable_service 'openstack-ceilometer-notification' }
      it { is_expected.to start_service 'openstack-ceilometer-notification' }
      it do
        expect(chef_run.service('openstack-ceilometer-central')).to \
          subscribe_to('template[/etc/ceilometer/ceilometer.conf]').on(:restart)
      end
      it do
        expect(chef_run.service('openstack-ceilometer-notification')).to \
          subscribe_to('template[/etc/ceilometer/ceilometer.conf]').on(:restart)
      end
      it { is_expected.to install_package 'patch' }
      it do
        is_expected.to run_execute('patch -p1 < /var/chef/cache/ceilometer-prometheus1.patch').with(
          cwd: '/usr/lib/python3.6/site-packages'
        )
      end
      it do
        is_expected.to run_execute('patch -p1 < /var/chef/cache/ceilometer-prometheus2.patch').with(
          cwd: '/usr/lib/python3.6/site-packages'
        )
      end

      context 'already patched' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
        end
        before do
          stub_command('grep -q curated_sname /usr/lib/python3.6/site-packages/ceilometer/publisher/prometheus.py').and_return(true)
          stub_command('grep -q s.project_id /usr/lib/python3.6/site-packages/ceilometer/publisher/prometheus.py').and_return(true)
        end
        it { is_expected.to_not run_execute('patch -p1 < /var/chef/cache/ceilometer-prometheus1.patch') }
        it { is_expected.to_not run_execute('patch -p1 < /var/chef/cache/ceilometer-prometheus2.patch') }
      end
    end
  end
end
