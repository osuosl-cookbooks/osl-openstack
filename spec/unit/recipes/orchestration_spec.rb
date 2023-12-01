require_relative '../../spec_helper'

describe 'osl-openstack::orchestration' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm) do |node|
          node.normal['osl-openstack']['cluster_name'] = 'x86'
        end.converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to add_osl_repos_openstack 'orchestration' }
      it { is_expected.to create_osl_openstack_client 'orchestration' }
      it { is_expected.to accept_osl_firewall_openstack 'orchestration' }
      it do
        is_expected.to create_osl_openstack_user('heat').with(
          domain_name: 'default',
          role_name: 'admin',
          project_name: 'service',
          password: 'heat'
        )
      end
      it { is_expected.to grant_role_osl_openstack_user 'heat' }
      it { is_expected.to create_osl_openstack_service('heat').with(type: 'orchestration') }
      it { is_expected.to create_osl_openstack_service('heat-cfn').with(type: 'cloudformation') }
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
      %w(
        admin
        internal
        public
      ).each do |int|
        it do
          is_expected.to create_osl_openstack_endpoint("orchestration-#{int}").with(
            endpoint_name: 'orchestration',
            service_name: 'heat',
            interface: int,
            url: 'http://controller.example.com:8004/v1/%(tenant_id)s',
            region: 'RegionOne'
          )
        end
        it do
          is_expected.to create_osl_openstack_endpoint("cloudformation-#{int}").with(
            endpoint_name: 'cloudformation',
            service_name: 'heat-cfn',
            interface: int,
            url: 'http://controller.example.com:8000/v1',
            region: 'RegionOne'
          )
        end
      end
      it do
        is_expected.to install_package(
          %w(
            openstack-heat-api
            openstack-heat-api-cfn
            openstack-heat-engine
          )
        )
      end
      it do
        is_expected.to create_template('/etc/heat/heat.conf').with(
          owner: 'root',
          group: 'heat',
          mode: '0640',
          sensitive: true,
          variables: {
              auth_encryption_key: '4CFk1URr4Ln37kKRNSypwjI7vv7jfLQE',
              auth_endpoint: 'controller.example.com',
              database_connection: 'mysql+pymysql://heat:heat@localhost:3306/x86_heat',
              endpoint: 'controller.example.com',
              heat_domain_admin: 'heat_domain_admin',
              memcached_endpoint: 'controller.example.com:11211',
              service_pass: 'heat',
              transport_url: 'rabbit://openstack:openstack@controller.example.com:5672',
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
