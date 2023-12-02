require_relative '../../spec_helper'

describe 'osl-openstack::image' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm) do |node|
          node.normal['osl-openstack']['cluster_name'] = 'x86'
        end.converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to add_osl_repos_openstack 'image' }
      it { is_expected.to create_osl_openstack_client 'image' }
      it { is_expected.to accept_osl_firewall_openstack 'image' }
      it { is_expected.to include_recipe 'osl-ceph' }
      it do
        is_expected.to create_osl_openstack_user('glance').with(
          domain_name: 'default',
          role_name: 'admin',
          project_name: 'service',
          password: 'glance'
        )
      end
      it { is_expected.to grant_role_osl_openstack_user 'glance' }
      it { is_expected.to create_osl_openstack_service('glance').with(type: 'image') }
      %w(
        admin
        internal
        public
      ).each do |int|
        it do
          is_expected.to create_osl_openstack_endpoint("image-#{int}").with(
            endpoint_name: 'image',
            service_name: 'glance',
            interface: int,
            url: 'http://controller.example.com:9292',
            region: 'RegionOne'
          )
        end
      end
      it { is_expected.to install_package 'openstack-glance' }
      it do
        is_expected.to create_template('/etc/glance/glance-registry.conf').with(
          owner: 'root',
          group: 'glance',
          mode: '0640',
          sensitive: true,
          variables: {
              auth_endpoint: 'controller.example.com',
              database_connection: 'mysql+pymysql://glance_x86:glance@localhost:3306/glance_x86',
              memcached_endpoint: 'controller.example.com:11211',
              service_pass: 'glance',
              transport_url: 'rabbit://openstack:openstack@controller.example.com:5672',
          }
        )
      end
      it { expect(chef_run.template('/etc/glance/glance-registry.conf')).to notify('service[openstack-glance-registry]').to(:restart) }
      it do
        is_expected.to create_template('/etc/glance/glance-api.conf').with(
          owner: 'root',
          group: 'glance',
          mode: '0640',
          sensitive: true,
          variables: {
              auth_endpoint: 'controller.example.com',
              database_connection: 'mysql+pymysql://glance_x86:glance@localhost:3306/glance_x86',
              memcached_endpoint: 'controller.example.com:11211',
              rbd_store_pool: 'images',
              rbd_store_user: 'glance',
              service_pass: 'glance',
              transport_url: 'rabbit://openstack:openstack@controller.example.com:5672',
          }
        )
      end
      it { expect(chef_run.template('/etc/glance/glance-api.conf')).to notify('execute[glance: db_sync]').to(:run).immediately }
      it { expect(chef_run.template('/etc/glance/glance-api.conf')).to notify('service[openstack-glance-api]').to(:restart) }
      it do
        is_expected.to nothing_execute('glance: db_sync').with(
          command: 'glance-manage db_sync',
          user: 'glance',
          group: 'glance'
        )
      end
      it do
        is_expected.to modify_group('ceph-image').with(
          group_name: 'ceph',
          append: true,
          members: %w(glance)
        )
      end
      it { expect(chef_run.group('ceph-image')).to notify('service[openstack-glance-api]').to(:restart).immediately }
      it do
        is_expected.to create_osl_ceph_keyring('glance').with(
          key: 'AQANbr1aPR2EIhAASn5EW+qjhoXJAtIqGYE5jQ=='
        )
      end
      it { expect(chef_run.osl_ceph_keyring('glance')).to notify('service[openstack-glance-api]').to(:restart) }
      it { is_expected.to enable_service 'openstack-glance-api' }
      it { is_expected.to start_service 'openstack-glance-api' }
      it { is_expected.to enable_service 'openstack-glance-registry' }
      it { is_expected.to start_service 'openstack-glance-registry' }
    end
  end
end
