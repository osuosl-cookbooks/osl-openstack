require_relative '../../spec_helper'

describe 'osl-openstack::orchestration' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'

      it_behaves_like 'restarts on package upgrade', 'osuosl-openstack-heat', %w(openstack-heat-api openstack-heat-api-cfn openstack-heat-engine)

      it_behaves_like 'db sync on upgrade', 'heat', ['heat: db_sync']

      it do
        is_expected.to render_file('/etc/heat/heat.conf')
          .with_content(/^\[database\]\nconnection = .*\n#.*\nconnection_recycle_time = 300$/)
      end

      it_behaves_like 'oslo messaging config', '/etc/heat/heat.conf'
      it do
        is_expected.to render_file('/etc/heat/heat.conf').with_content { |c|
          authtoken = c[/^\[keystone_authtoken\]\n(?:[^\[].*\n)*/]
          expect(authtoken).to include("auth_type = v3password\n", "service_token_roles_required = True\n", "username = heat\n")
          expect(authtoken).to_not include('region_name')
        }
      end

      it { is_expected.to create_osl_openstack_client('orchestration').with(firewall: true, openrc: false) }
      it { is_expected.to create_osl_openstack_service_user('heat').with(password: 'heat') }
      it { is_expected.to create_osl_openstack_domain('heat') }
      it do
        is_expected.to create_osl_openstack_user('heat_domain_admin').with(
          domain_name: 'heat',
          role_name: 'admin',
          project_name: nil,
          password: 'heat_domain_admin'
        )
      end
      it { is_expected.to grant_domain_osl_openstack_user 'heat_domain_admin' }
      it { is_expected.to create_osl_openstack_role('heat_stack_owner') }
      it { is_expected.to create_osl_openstack_role('heat_stack_user') }
      it do
        is_expected.to create_osl_openstack_api('heat').with(
          type: 'orchestration',
          endpoint_name: 'orchestration',
          url: 'http://controller.testing.osuosl.org:8004/v1/%(tenant_id)s',
          region: 'RegionOne'
        )
      end
      it do
        is_expected.to create_osl_openstack_api('heat-cfn').with(
          type: 'cloudformation',
          endpoint_name: 'cloudformation',
          url: 'http://controller.testing.osuosl.org:8000/v1',
          region: 'RegionOne'
        )
      end
      it { is_expected.to upgrade_package 'osuosl-openstack-heat' }
      it do
        is_expected.to create_template('/etc/heat/heat.conf').with(
          owner: 'root',
          group: 'heat',
          mode: '0640',
          sensitive: true,
          variables: {
            auth_encryption_key: '4CFk1URr4Ln37kKRNSypwjI7vv7jfLQE',
            auth_endpoint: 'controller.testing.osuosl.org',
            database_connection: 'mysql+pymysql://heat_x86:heat@localhost:3306/heat_x86',
            endpoint: 'controller.testing.osuosl.org',
            heat_domain_admin: 'heat_domain_admin',
            listen_ip: '*',
            memcached_endpoint: 'controller.testing.osuosl.org:11211',
            region: 'RegionOne',
            service_pass: 'heat',
            **messaging_vars,
          }
        )
      end
      it { expect(chef_run.template('/etc/heat/heat.conf')).to notify('execute[heat: db_sync]').to(:run).immediately }
      it do
        is_expected.to nothing_execute('heat: db_sync').with(
          command: 'heat-manage db_sync',
          user: 'heat',
          group: 'heat'
        )
      end
      %w(
        openstack-heat-api
        openstack-heat-api-cfn
        openstack-heat-engine
      ).each do |srv|
        it { is_expected.to enable_service srv }
        it { is_expected.to start_service srv }
        it do
          expect(chef_run.service(srv)).to \
            subscribe_to('template[/etc/heat/heat.conf]').on(:restart)
        end
      end
    end
  end
end
