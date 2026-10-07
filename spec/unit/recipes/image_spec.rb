require_relative '../../spec_helper'

describe 'osl-openstack::image' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'

      it_behaves_like 'db sync on upgrade', 'glance', ['glance: db_sync']

      it do
        is_expected.to render_file('/etc/glance/glance-api.conf')
          .with_content(/^\[database\]\nconnection = .*\n#.*\nconnection_recycle_time = 300$/)
      end

      it { is_expected.to create_osl_openstack_client('image').with(firewall: true, openrc: true) }
      it { is_expected.to include_recipe 'osl-ceph' }
      it { is_expected.to create_osl_openstack_service_user('glance').with(password: 'glance') }
      it do
        is_expected.to create_osl_openstack_api('glance').with(
          type: 'image',
          endpoint_name: 'image',
          url: 'http://controller.testing.osuosl.org:9292',
          region: 'RegionOne'
        )
      end
      it { is_expected.to upgrade_package 'osuosl-openstack-glance' }
      it do
        is_expected.to create_template('/etc/glance/glance-api.conf').with(
          owner: 'root',
          group: 'glance',
          mode: '0640',
          sensitive: true,
          variables: {
            auth_endpoint: 'controller.testing.osuosl.org',
            listen_ip: '*',
            local_storage: false,
            database_connection: 'mysql+pymysql://glance_x86:glance@localhost:3306/glance_x86',
            memcached_endpoint: 'controller.testing.osuosl.org:11211',
            rbd_store_pool: 'images',
            rbd_store_user: 'glance',
            service_pass: 'glance',
            **messaging_vars,
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
      it_behaves_like 'oslo messaging config', '/etc/glance/glance-api.conf'
      it { is_expected.to render_file('/etc/glance/glance-api.conf').with_content(/^default_backend = rbd$/) }
      it { is_expected.to_not render_file('/etc/glance/glance-api.conf').with_content(/enable_v[12]_api|default_store/) }
      it do
        is_expected.to render_file('/etc/glance/glance-api.conf').with_content { |c|
          expect(c[/^\[keystone_authtoken\]\n(?:[^\[].*\n)*/]).to include(
            "auth_type = password\n", "region_name = RegionOne\n", "service_token_roles_required = true\n", "username = glance\n"
          )
        }
      end

      context 'with quorum queues and TLS enabled' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            openstack_secrets_stub(
              'messaging' => {
                'quorum_queues' => true,
                'tls' => true,
                'ssl_ca_file' => '/etc/pki/tls/certs/osl-chain.pem',
              }
            )
          )
        end

        it do
          is_expected.to create_template('/etc/glance/glance-api.conf').with(
            variables: hash_including(
              rabbit_quorum_queue: true,
              rabbit_tls: true,
              rabbit_ssl_ca_file: '/etc/pki/tls/certs/osl-chain.pem',
              transport_url: 'rabbit://openstack:openstack@controller.testing.osuosl.org:5671/'
            )
          )
        end
        it { is_expected.to render_file('/etc/glance/glance-api.conf').with_content('[oslo_messaging_rabbit]') }
        it { is_expected.to render_file('/etc/glance/glance-api.conf').with_content('rabbit_quorum_queue = true') }
        it { is_expected.to render_file('/etc/glance/glance-api.conf').with_content(/^ssl = true$/) }
        it { is_expected.to render_file('/etc/glance/glance-api.conf').with_content('ssl_ca_file = /etc/pki/tls/certs/osl-chain.pem') }
      end

      context 'region2 w/o ceph' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['fqdn'] = 'node1.testing.osuosl.org'
          end.converge(described_recipe)
        end

        include_context 'region2_stubs'

        it do
          is_expected.to create_osl_openstack_api('glance').with(
            type: 'image',
            endpoint_name: 'image',
            url: 'http://controller_region2.testing.osuosl.org:9292',
            region: 'RegionTwo'
          )
        end

        it do
          is_expected.to create_template('/etc/glance/glance-api.conf').with(
            owner: 'root',
            group: 'glance',
            mode: '0640',
            sensitive: true,
            variables: {
              auth_endpoint: 'controller.testing.osuosl.org',
              listen_ip: '*',
              local_storage: true,
              database_connection: 'mysql+pymysql://glance_x86:glance@localhost_region2:3306/glance_x86',
              memcached_endpoint: 'controller_region2.testing.osuosl.org:11211',
              rbd_store_pool: nil,
              rbd_store_user: nil,
              service_pass: 'glance',
              **messaging_vars(CONTROLLER_REGION2),
            }
          )
        end

        it { is_expected.to_not create_group 'ceph-image' }
        it { is_expected.to_not create_osl_ceph_keyring 'glance' }
      end

      context 'stepping into the client, service user and api resources' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.merge(
            step_into: %w(osl_openstack_client osl_openstack_service_user osl_openstack_api)
          )).converge(described_recipe)
        end

        it { is_expected.to add_osl_repos_openstack('default').with(source: :osuosl) }
        it { is_expected.to upgrade_package %w(osuosl-openstack-cli osuosl-openstack-selinux) }
        it { is_expected.to create_osl_openstack_openrc 'image' }
        it { is_expected.to accept_osl_firewall_openstack 'image' }
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
        %w(admin internal public).each do |int|
          it do
            is_expected.to create_osl_openstack_endpoint("image-#{int}").with(
              endpoint_name: 'image',
              service_name: 'glance',
              interface: int,
              url: 'http://controller.testing.osuosl.org:9292',
              region: 'RegionOne'
            )
          end
        end
      end
    end
  end
end
