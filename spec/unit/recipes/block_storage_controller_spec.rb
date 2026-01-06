require_relative '../../spec_helper'

describe 'osl-openstack::block_storage_controller' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to add_osl_repos_openstack 'block-storage-controller' }
      it { is_expected.to create_osl_openstack_client 'block-storage-controller' }
      it { is_expected.to accept_osl_firewall_openstack 'block-storage-controller' }
      it { is_expected.to include_recipe 'osl-apache' }
      it { is_expected.to include_recipe 'osl-apache::mod_wsgi' }
      it do
        is_expected.to create_osl_openstack_user('cinder').with(
          domain_name: 'default',
          role_name: 'admin',
          project_name: 'service',
          password: 'cinder'
        )
      end
      it { is_expected.to grant_role_osl_openstack_user 'cinder' }
      it { is_expected.to create_osl_openstack_service('cinderv2').with(type: 'volumev2') }
      it { is_expected.to create_osl_openstack_service('cinderv3').with(type: 'volumev3') }
      %w(
        admin
        internal
        public
      ).each do |int|
        it do
          is_expected.to create_osl_openstack_endpoint("volumev2-#{int}").with(
            endpoint_name: 'volumev2',
            service_name: 'cinderv2',
            interface: int,
            url: 'http://controller.testing.osuosl.org:8776/v2/%(project_id)s',
            region: 'RegionOne'
          )
        end
        it do
          is_expected.to create_osl_openstack_endpoint("volumev3-#{int}").with(
            endpoint_name: 'volumev3',
            service_name: 'cinderv3',
            interface: int,
            url: 'http://controller.testing.osuosl.org:8776/v3/%(project_id)s',
            region: 'RegionOne'
          )
        end
      end
      it { is_expected.to include_recipe 'osl-openstack::block_storage_common' }
      it { is_expected.to install_package 'openstack-cinder' }
      it do
        is_expected.to create_template('/etc/cinder/cinder.conf').with(
          owner: 'root',
          group: 'cinder',
          mode: '0640',
          sensitive: true,
          variables: {
              auth_endpoint: 'controller.testing.osuosl.org',
              backup_ceph_pool: 'backups',
              backup_ceph_user: 'cinder-backup',
              block_rbd_pool: 'volumes',
              block_ssd_rbd_pool: 'volumes_ssd',
              compute_pass: 'nova',
              database_connection: 'mysql+pymysql://cinder_x86:cinder@localhost:3306/cinder_x86',
              image_endpoint: 'controller.testing.osuosl.org',
              memcached_endpoint: 'controller.testing.osuosl.org:11211',
              rbd_secret_uuid: '8102bb29-f48b-4f6e-81d7-4c59d80ec6b8',
              rbd_user: 'cinder',
              region: 'RegionOne',
              service_pass: 'cinder',
              transport_url: 'rabbit://openstack:openstack@controller.testing.osuosl.org:5672',
          }
        )
      end
      it do
        is_expected.to nothing_execute('cinder: db_sync').with(
          command: 'cinder-manage db sync',
          user: 'cinder',
          group: 'cinder'
        )
      end
      it do
        expect(chef_run.execute('cinder: db_sync')).to \
          subscribe_to('template[/etc/cinder/cinder.conf]').on(:run).immediately
      end
      it do
        is_expected.to create_apache_app('cinder-api').with(
          cookbook: 'osl-openstack',
          template: 'wsgi-cinder-api.conf.erb'
        )
      end
      it do
        expect(chef_run.apache_app('cinder-api')).to notify('apache2_service[block_storage]').to(:reload).immediately
      end
      it { is_expected.to nothing_apache2_service('block_storage') }
      it do
        expect(chef_run.apache2_service('block_storage')).to \
          subscribe_to('template[/etc/cinder/cinder.conf]').on(:reload)
      end
      it { is_expected.to enable_service 'openstack-cinder-scheduler' }
      it { is_expected.to start_service 'openstack-cinder-scheduler' }
      it do
        expect(chef_run.service('openstack-cinder-scheduler')).to \
          subscribe_to('template[/etc/cinder/cinder.conf]').on(:restart)
      end
    end
  end
end
