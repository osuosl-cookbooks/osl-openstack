require_relative '../../spec_helper'

describe 'osl-openstack::compute_controller' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm) do |node|
          node.normal['osl-openstack']['node_type'] = 'controller'
        end.converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to add_osl_repos_openstack 'compute' }
      it { is_expected.to create_osl_openstack_client 'compute' }
      it { is_expected.to accept_osl_firewall_openstack 'compute' }
      it { is_expected.to include_recipe 'osl-apache' }
      it { is_expected.to include_recipe 'osl-apache::mod_wsgi' }
      it do
        is_expected.to create_osl_openstack_user('nova').with(
          domain_name: 'default',
          role_name: 'admin',
          project_name: 'service',
          password: 'nova'
        )
      end
      it do
        is_expected.to create_osl_openstack_user('placement').with(
          domain_name: 'default',
          role_name: 'admin',
          project_name: 'service',
          password: 'placement'
        )
      end
      it { is_expected.to grant_role_osl_openstack_user 'nova' }
      it { is_expected.to grant_role_osl_openstack_user 'placement' }
      it { is_expected.to create_osl_openstack_service('nova').with(type: 'compute') }
      it { is_expected.to create_osl_openstack_service('placement').with(type: 'placement') }
      %w(
        admin
        internal
        public
      ).each do |int|
        it do
          is_expected.to create_osl_openstack_endpoint("placement-#{int}").with(
            endpoint_name: 'placement',
            service_name: 'placement',
            interface: int,
            url: 'http://controller.example.com:8778',
            region: 'RegionOne'
          )
        end
        it do
          is_expected.to create_osl_openstack_endpoint("compute-#{int}").with(
            endpoint_name: 'compute',
            service_name: 'nova',
            interface: int,
            url: 'http://controller.example.com:8774/v2.1',
            region: 'RegionOne'
          )
        end
      end
      it do
        is_expected.to install_package %w(
          openstack-nova-api
          openstack-nova-conductor
          openstack-nova-novncproxy
          openstack-nova-scheduler
          openstack-placement-api
          python3-osc-placement
        )
      end
      it { is_expected.to delete_file('/etc/httpd/conf.d/00-placement-api.conf') }
      it do
        expect(chef_run.file('/etc/httpd/conf.d/00-placement-api.conf')).to notify('apache2_service[compute]').to(:reload)
      end
      it do
        expect(chef_run.file('/etc/httpd/conf.d/00-placement-api.conf')).to \
          notify('directory[purge distro conf.d]').to(:delete).immediately
      end
      it { is_expected.to nothing_directory('purge distro conf.d').with(path: '/etc/httpd/conf.d', recursive: true) }
      it do
        is_expected.to create_template('/etc/placement/placement.conf').with(
          owner: 'root',
          group: 'placement',
          mode: '0640',
          sensitive: true,
          variables: {
              auth_endpoint: 'controller.example.com',
              database_connection: 'mysql+pymysql://placement_x86:placement@localhost:3306/placement_x86',
              memcached_endpoint: 'controller.example.com:11211',
              service_pass: 'placement',
          }
        )
      end
      it do
        expect(chef_run.template('/etc/placement/placement.conf')).to notify('execute[placement: db_sync]').to(:run).immediately
      end
      it do
        expect(chef_run.template('/etc/placement/placement.conf')).to notify('apache2_service[compute]').to(:reload)
      end
      it do
        is_expected.to edit_delete_lines('remove dhcpbridge').with(
          path: '/usr/share/nova/nova-dist.conf',
          pattern: '^dhcpbridge.*',
          backup: true
        )
      end
      it do
        is_expected.to edit_delete_lines('remove force_dhcp_release').with(
          path: '/usr/share/nova/nova-dist.conf',
          pattern: '^force_dhcp_release.*',
          backup: true
        )
      end
      it do
        is_expected.to create_template('/etc/nova/nova.conf').with(
          owner: 'root',
          group: 'nova',
          mode: '0640',
          sensitive: true,
          variables: {
              allow_resize_to_same_host: nil,
              api_database_connection: 'mysql+pymysql://nova_x86:nova@localhost:3306/nova_api_x86',
              auth_endpoint: 'controller.example.com',
              cinder_disabled: false,
              compute: false,
              cpu_allocation_ratio: nil,
              database_connection: 'mysql+pymysql://nova_x86:nova@localhost:3306/nova_x86',
              disk_allocation_ratio: '1.5',
              endpoint: 'controller.example.com',
              enabled_filters: %w(
                AggregateInstanceExtraSpecsFilter
                PciPassthroughFilter
                AvailabilityZoneFilter
                ComputeFilter
                ComputeCapabilitiesFilter
                ImagePropertiesFilter
                ServerGroupAntiAffinityFilter
                ServerGroupAffinityFilter
              ),
              image_endpoint: 'controller.example.com',
              images_rbd_pool: 'vms',
              local_storage: false,
              memcached_endpoint: 'controller.example.com:11211',
              metadata_proxy_shared_secret: '2SJh0RuO67KpZ63z',
              neutron_pass: 'neutron',
              pci_alias: nil,
              pci_passthrough_whitelist: nil,
              placement_pass: 'placement',
              power10: false,
              ram_allocation_ratio: nil,
              rbd_secret_uuid: '8102bb29-f48b-4f6e-81d7-4c59d80ec6b8',
              rbd_user: 'cinder',
              region: 'RegionOne',
              service_pass: 'nova',
              transport_url: 'rabbit://openstack:openstack@controller.example.com:5672',
          }
        )
      end
      it 'is expected to not render pci config' do
        is_expected.to_not render_file('/etc/nova/nova.conf').with_content('[pci]')
        is_expected.to_not render_file('/etc/nova/nova.conf').with_content(/^alias =/)
        is_expected.to_not render_file('/etc/nova/nova.conf').with_content(/^passthrough_whitelist =/)
      end
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content('images_rbd_pool = vms') }
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content('ram_allocation_ratio = 1') }
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content('server_listen = 0.0.0.0') }
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content('server_proxyclient_address = 10.0.0.2') }
      it do
        is_expected.to nothing_execute('placement: db_sync').with(
          command: 'placement-manage db sync',
          user: 'placement',
          group: 'placement'
        )
      end
      it do
        is_expected.to nothing_execute('nova: api_db_sync').with(
          command: 'nova-manage api_db sync',
          user: 'nova',
          group: 'nova'
        )
      end
      it do
        is_expected.to nothing_execute('nova: register cell0').with(
          command: 'nova-manage cell_v2 map_cell0 --database_connection mysql+pymysql://nova_x86:nova@localhost:3306/nova_cell0_x86',
          sensitive: true,
          user: 'nova',
          group: 'nova'
        )
      end
      it do
        is_expected.to nothing_execute('nova: create cell1').with(
          command: 'nova-manage cell_v2 create_cell --name=cell1',
          user: 'nova',
          group: 'nova'
        )
      end
      it do
        is_expected.to nothing_execute('nova: db_sync').with(
          command: 'nova-manage db sync',
          user: 'nova',
          group: 'nova'
        )
      end
      it do
        is_expected.to nothing_execute('nova: discover hosts').with(
          command: 'nova-manage cell_v2 discover_hosts',
          user: 'nova',
          group: 'nova'
        )
      end
      it { expect(chef_run.execute('nova: api_db_sync')).to subscribe_to('template[/etc/nova/nova.conf]').on(:run).immediately }
      it { expect(chef_run.execute('nova: register cell0')).to subscribe_to('template[/etc/nova/nova.conf]').on(:run).immediately }
      it { expect(chef_run.execute('nova: create cell1')).to subscribe_to('template[/etc/nova/nova.conf]').on(:run).immediately }
      it { expect(chef_run.execute('nova: db_sync')).to subscribe_to('template[/etc/nova/nova.conf]').on(:run).immediately }
      it { expect(chef_run.execute('nova: discover hosts')).to subscribe_to('template[/etc/nova/nova.conf]').on(:run).immediately }
      it do
        is_expected.to create_apache_app('placement').with(
          cookbook: 'osl-openstack',
          template: 'wsgi-placement.conf.erb'
        )
      end
      it do
        is_expected.to create_apache_app('nova-api').with(
          cookbook: 'osl-openstack',
          template: 'wsgi-nova-api.conf.erb'
        )
      end
      it do
        is_expected.to create_apache_app('nova-metadata').with(
          cookbook: 'osl-openstack',
          template: 'wsgi-nova-metadata.conf.erb'
        )
      end
      it { expect(chef_run.apache_app('placement')).to notify('apache2_service[compute]').to(:reload).immediately }
      it { expect(chef_run.apache_app('nova-api')).to notify('apache2_service[compute]').to(:reload).immediately }
      it { expect(chef_run.apache_app('nova-metadata')).to notify('apache2_service[compute]').to(:reload).immediately }
      %w(
        openstack-nova-conductor
        openstack-nova-novncproxy
        openstack-nova-scheduler
      ).each do |srv|
        it { is_expected.to enable_service srv }
        it { is_expected.to start_service srv }
        it { expect(chef_run.service(srv)).to subscribe_to('delete_lines[remove dhcpbridge]').on(:restart) }
        it { expect(chef_run.service(srv)).to subscribe_to('delete_lines[remove force_dhcp_release]').on(:restart) }
        it { expect(chef_run.service(srv)).to subscribe_to('template[/etc/nova/nova.conf]').on(:restart) }
      end
      it do
        is_expected.to create_certificate_manage('novnc').with(
          cert_path: '/etc/nova/pki',
          cert_file: 'novnc.pem',
          key_file: 'novnc.key',
          chain_file: 'novnc-bundle.crt',
          nginx_cert: true,
          owner: 'nova',
          group: 'nova'
        )
      end
      it { expect(chef_run.certificate_manage('novnc')).to notify('service[openstack-nova-novncproxy]').to(:restart) }
      it do
        is_expected.to create_template('/etc/sysconfig/openstack-nova-novncproxy').with(
          source: 'novncproxy.erb',
          variables: {
            cert: '/etc/nova/pki/certs/novnc.pem',
            key: '/etc/nova/pki/private/novnc.key',
          }
        )
      end
      it do
        expect(chef_run.template('/etc/sysconfig/openstack-nova-novncproxy')).to \
          notify('service[openstack-nova-novncproxy]').to(:restart)
      end
      it do
        is_expected.to create_cron_d('nova-rowsflush').with(
          minute: 20,
          hour: 5,
          user: 'nova',
          command: "nova-manage db archive_deleted_rows --max_rows 1000 --before `date --date='today - 90 days' +\\%F` --until-complete --all-cells >>/var/log/nova/nova-rowsflush.log 2>&1"
        )
      end
      it do
        is_expected.to create_cron_d('nova-rowspurge').with(
          minute: 20,
          hour: 6,
          user: 'nova',
          command: "nova-manage db purge --before `date --date='today - 14 days' +\\%D` --all-cells >>/var/log/nova/nova-rowspurge.log 2>&1"
        )
      end

      context 'pci passthrough' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['fqdn'] = 'controller2.example.com'
          end.converge(described_recipe)
        end

        it 'is expected to render pci config' do
          is_expected.to render_file('/etc/nova/nova.conf').with_content('[pci]')
          is_expected.to render_file('/etc/nova/nova.conf').with_content('alias = { "vendor_id": "10de", "product_id": "1db5", "device_type": "type-PCI", "name": "gpu_nvidia_v100" }')
          is_expected.to_not render_file('/etc/nova/nova.conf').with_content(/^passthrough_whitelist =/)
        end

        context 'compute node & local storage' do
          cached(:chef_run) do
            ChefSpec::SoloRunner.new(pltfrm) do |node|
              node.automatic['fqdn'] = 'node1.example.com'
            end.converge(described_recipe)
          end

          it 'is expected to render pci config' do
            is_expected.to render_file('/etc/nova/nova.conf').with_content('[pci]')
            is_expected.to render_file('/etc/nova/nova.conf').with_content('alias = { "vendor_id": "10de", "product_id": "1db5", "device_type": "type-PCI", "name": "gpu_nvidia_v100" }')
            is_expected.to render_file('/etc/nova/nova.conf').with_content('passthrough_whitelist = { "vendor_id": "10de", "product_id": "1db5" }')
          end
          it { is_expected.to_not render_file('/etc/nova/nova.conf').with_content('images_rbd_pool = vms') }
        end
      end

      context 'region2' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['fqdn'] = 'node1.example.com'
            node.normal['osl-openstack']['node_type'] = 'controller'
          end.converge(described_recipe)
        end

        include_context 'region2_stubs'
        it do
          is_expected.to create_template('/etc/nova/nova.conf').with(
            owner: 'root',
            group: 'nova',
            mode: '0640',
            sensitive: true,
            variables: {
                allow_resize_to_same_host: nil,
                api_database_connection: 'mysql+pymysql://nova_x86:nova@localhost_region2:3306/nova_api_x86',
                auth_endpoint: 'controller.example.com',
                cinder_disabled: true,
                compute: false,
                cpu_allocation_ratio: nil,
                database_connection: 'mysql+pymysql://nova_x86:nova@localhost_region2:3306/nova_x86',
                disk_allocation_ratio: '1.5',
                endpoint: 'controller_region2.example.com',
                enabled_filters: %w(
                  AggregateInstanceExtraSpecsFilter
                  PciPassthroughFilter
                  AvailabilityZoneFilter
                  ComputeFilter
                  ComputeCapabilitiesFilter
                  ImagePropertiesFilter
                  ServerGroupAntiAffinityFilter
                  ServerGroupAffinityFilter
                ),
                image_endpoint: 'controller_region2.example.com',
                images_rbd_pool: nil,
                local_storage: true,
                memcached_endpoint: 'controller_region2.example.com:11211',
                metadata_proxy_shared_secret: '2SJh0RuO67KpZ63z',
                neutron_pass: 'neutron',
                pci_alias: '{ "vendor_id": "10de", "product_id": "1db5", "device_type": "type-PCI", "name": "gpu_nvidia_v100" }',
                pci_passthrough_whitelist: '{ "vendor_id": "10de", "product_id": "1db5" }',
                placement_pass: 'placement',
                power10: false,
                ram_allocation_ratio: nil,
                rbd_secret_uuid: nil,
                rbd_user: nil,
                region: 'RegionTwo',
                service_pass: 'nova',
                transport_url: 'rabbit://openstack:openstack@controller_region2.example.com:5672',
            }
          )
        end
      end
    end
  end
end
