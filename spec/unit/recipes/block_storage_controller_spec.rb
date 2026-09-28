require_relative '../../spec_helper'

describe 'osl-openstack::block_storage_controller' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm.merge(step_into: %w(apache_app))).converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to create_osl_openstack_client('block-storage-controller').with(firewall: true, openrc: false) }
      it { is_expected.to include_recipe 'osl-apache' }
      it { is_expected.to include_recipe 'osl-apache::mod_wsgi' }
      it { is_expected.to create_osl_openstack_service_user('cinder').with(password: 'cinder') }
      it do
        is_expected.to create_osl_openstack_api('cinderv2').with(
          type: 'volumev2',
          endpoint_name: 'volumev2',
          url: 'http://controller.testing.osuosl.org:8776/v2/%(project_id)s',
          region: 'RegionOne'
        )
      end
      it do
        is_expected.to create_osl_openstack_api('cinderv3').with(
          type: 'volumev3',
          endpoint_name: 'volumev3',
          url: 'http://controller.testing.osuosl.org:8776/v3/%(project_id)s',
          region: 'RegionOne'
        )
      end
      it { is_expected.to include_recipe 'osl-openstack::block_storage_common' }
      it { is_expected.to install_package 'osuosl-openstack-cinder' }
      it { is_expected.to install_package 'python3-redis' }
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
            cluster: nil,
            compute_pass: 'nova',
            coordination_url: nil,
            database_connection: 'mysql+pymysql://cinder_x86:cinder@localhost:3306/cinder_x86',
            image_api_servers: 'http://controller.testing.osuosl.org:9292',
            memcached_endpoint: 'controller.testing.osuosl.org:11211',
            rbd_secret_uuid: '8102bb29-f48b-4f6e-81d7-4c59d80ec6b8',
            rbd_user: 'cinder',
            region: 'RegionOne',
            service_pass: 'cinder',
            **messaging_vars,
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
          template: 'wsgi-api.conf.erb',
          template_params: hash_including(port: 8776, group: 'cinder-wsgi', user: 'cinder')
        )
      end
      it do
        is_expected.to render_file('/etc/httpd/sites-available/cinder-api.conf')
          .with_content("Listen *:8776\n\n<VirtualHost *:8776>\n  WSGIProcessGroup cinder-wsgi\n")
          .with_content('WSGIDaemonProcess cinder-wsgi processes=2 threads=10 user=cinder group=cinder')
          .with_content('WSGIScriptAlias / /usr/bin/cinder-wsgi')
          .with_content('rotatelogs /var/log/httpd/cinder-api/access/')
          .with_content("</VirtualHost>\n\nWSGISocketPrefix /var/lock/subsys\n")
      end
      it do
        expect(chef_run.apache_app('cinder-api')).to notify('apache2_service[block_storage]').to(:reload).immediately
      end
      it { is_expected.to nothing_apache2_service('block_storage') }
      it { is_expected.to_not render_file('/etc/cinder/cinder.conf').with_content(/^\[libvirt\]$/) }
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
      it { is_expected.to_not render_file('/etc/cinder/cinder.conf').with_content(/^\[coordination\]$/) }

      context 'valkey coordination' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            openstack_secrets_stub(
              'coordination' => coordination_tier_secrets('db' => 1)
            )
          )
        end

        it do
          is_expected.to render_file('/etc/cinder/cinder.conf').with_content(
            'backend_url = redis://:oslocks@mq1.testing.osuosl.org:26379' \
            '?sentinel=oslocks' \
            '&sentinel_fallback=mq2.testing.osuosl.org:26379' \
            '&sentinel_fallback=mq3.testing.osuosl.org:26379' \
            '&db=1'
          )
        end
      end
    end
  end
end
