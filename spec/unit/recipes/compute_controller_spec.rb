require_relative '../../spec_helper'

describe 'osl-openstack::compute_controller' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm.merge(step_into: %w(apache_app))) do |node|
          node.normal['osl-openstack']['node_type'] = 'controller'
        end.converge(described_recipe)
      end

      include_context 'common_stubs'

      it_behaves_like 'restarts on package upgrade', 'osuosl-openstack-placement', ['placement-uwsgi']
      it_behaves_like 'restarts on package upgrade', 'osuosl-openstack-nova-controller', %w(openstack-nova-api openstack-nova-metadata openstack-nova-conductor openstack-nova-novncproxy openstack-nova-scheduler)

      it_behaves_like 'db sync on upgrade', 'placement', ['placement: db_sync']
      it_behaves_like 'db sync on upgrade', 'nova', ['nova: api_db_sync', 'nova: db_sync']

      it do
        is_expected.to render_file('/etc/nova/nova.conf')
          .with_content(/^\[database\]\nconnection = .*\n#.*\nconnection_recycle_time = 300$/)
      end
      it do
        is_expected.to render_file('/etc/nova/nova.conf')
          .with_content(/^\[api_database\]\nconnection = .*\n#.*\nconnection_recycle_time = 300$/)
      end
      it do
        is_expected.to render_file('/etc/placement/placement.conf')
          .with_content(/^\[placement_database\]\nconnection = .*\n#.*\nconnection_recycle_time = 300$/)
      end

      it { is_expected.to create_osl_openstack_client('compute').with(firewall: true, openrc: false) }
      it { is_expected.to include_recipe 'osl-apache' }
      it { is_expected.to include_recipe 'osl-apache::mod_proxy_uwsgi' }
      it { is_expected.to create_osl_openstack_service_user('nova').with(password: 'nova') }
      it { is_expected.to create_osl_openstack_service_user('placement').with(password: 'placement') }
      it do
        is_expected.to create_osl_openstack_api('placement').with(
          type: 'placement',
          endpoint_name: 'placement',
          url: 'http://controller.testing.osuosl.org:8778',
          region: 'RegionOne'
        )
      end
      it do
        is_expected.to create_osl_openstack_api('nova').with(
          type: 'compute',
          endpoint_name: 'compute',
          url: 'http://controller.testing.osuosl.org:8774/v2.1',
          region: 'RegionOne'
        )
      end
      %w(osuosl-openstack-nova-controller osuosl-openstack-placement).each do |pkg|
        it { is_expected.to upgrade_package pkg }
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
            auth_endpoint: 'controller.testing.osuosl.org',
            database_connection: 'mysql+pymysql://placement_x86:placement@localhost:3306/placement_x86',
            memcached_endpoint: 'controller.testing.osuosl.org:11211',
            service_pass: 'placement',
          }
        )
      end
      it do
        expect(chef_run.template('/etc/placement/placement.conf')).to notify('execute[placement: db_sync]').to(:run).immediately
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
          variables: nova_conf_vars
        )
      end
      it 'is expected to not render pci config' do
        is_expected.to_not render_file('/etc/nova/nova.conf').with_content('[pci]')
        is_expected.to_not render_file('/etc/nova/nova.conf').with_content(/^alias =/)
        is_expected.to_not render_file('/etc/nova/nova.conf').with_content(/^passthrough_whitelist =/)
      end
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content('images_rbd_pool = vms') }
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content("state_path = /var/lib/nova\n") }
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content('ram_allocation_ratio = 1') }
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content('server_listen = 0.0.0.0') }
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content('server_proxyclient_address = 10.0.0.2') }
      it { is_expected.to render_file('/etc/nova/nova.conf').with_content(/^\[upgrade_levels\]\n#.*\ncompute = auto$/) }
      it do
        is_expected.to render_file('/etc/nova/nova.conf').with_content(
          %r{^\[privsep_osbrick\]\n#.*\nhelper_command = sudo nova-rootwrap /etc/nova/rootwrap.conf privsep-helper --config-file /etc/nova/nova.conf$}
        )
      end
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
          command: %w(nova-manage cell_v2 map_cell0 --database_connection mysql+pymysql://nova_x86:nova@localhost:3306/nova_cell0_x86),
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
      {
        'placement' => [8778, 'placement', 'placement', 'placement-uwsgi', '/etc/placement/placement-uwsgi.ini', '/run/placement/uwsgi.sock', 'placement-api', nil],
        'nova-api' => [8774, 'nova', 'nova-controller', 'openstack-nova-api', '/etc/nova/nova-api-uwsgi.ini', '/run/nova/api-uwsgi.sock', 'nova-api-wsgi', true],
        'nova-metadata' => [8775, 'nova', 'nova-controller', 'openstack-nova-metadata', '/etc/nova/nova-metadata-uwsgi.ini', '/run/nova/metadata-uwsgi.sock', 'nova-metadata-wsgi', true],
      }.each do |app, (port, user, venv, srv, ini, sock, script, pthread)|
        it do
          is_expected.to create_template(ini).with(
            source: 'uwsgi.ini.erb',
            group: user,
            mode: '0640',
            variables: {
              chdir: "/opt/openstack/#{venv}",
              wsgi_file: "/opt/openstack/#{venv}/bin/#{script}",
              socket: sock,
              user: user,
              processes: 6,
              threads: 1,
              env: { 'XDG_CACHE_HOME' => "/var/cache/httpd/osuosl-#{app}" }.merge(
                pthread ? { 'OS_OSLO_MESSAGING_RABBIT__HEARTBEAT_IN_PTHREAD' => 'true' } : {}
              ),
            }
          )
        end
        it do
          is_expected.to create_directory("/var/cache/httpd/osuosl-#{app}").with(owner: user, group: user, mode: '0750')
        end
        it { is_expected.to render_file(ini).with_content("env = XDG_CACHE_HOME=/var/cache/httpd/osuosl-#{app}\n") }
        # Only nova's eventlet-patched WSGI apps need the pthread heartbeat
        if pthread
          it { is_expected.to render_file(ini).with_content("env = OS_OSLO_MESSAGING_RABBIT__HEARTBEAT_IN_PTHREAD=true\n") }
        else
          it { is_expected.to_not render_file(ini).with_content('HEARTBEAT_IN_PTHREAD') }
        end
        it do
          is_expected.to render_file(ini)
            .with_content("wsgi-file = /opt/openstack/#{venv}/bin/#{script}\n")
            .with_content("socket = #{sock}\nchmod-socket = 660\nchown-socket = #{user}:apache\n")
            .with_content("processes = 6\nthreads = 1\n")
            .with_content('hook-master-start = unix_signal:3 kill_them_all')
        end
        it { expect(chef_run.template(ini)).to notify("service[#{srv}]").to(:restart) }
        it { is_expected.to enable_service srv }
        it { is_expected.to start_service srv }
        it do
          is_expected.to create_apache_app(app).with(
            cookbook: 'osl-openstack',
            template: 'wsgi-api.conf.erb',
            template_params: hash_including(port: port, socket: sock)
          )
        end
        it do
          is_expected.to render_file("/etc/httpd/sites-available/#{app}.conf")
            .with_content("Listen *:#{port}\n\n<VirtualHost *:#{port}>\n")
            .with_content(%(  ProxyPass / "unix:#{sock}|uwsgi://localhost/" retry=0\n))
            .with_content("<Proxy \"*\">\n    Require all granted\n  </Proxy>")
            .with_content(%r{rotatelogs /var/log/httpd/#{app}(-api)?/error/})
        end
        it { is_expected.to_not render_file("/etc/httpd/sites-available/#{app}.conf").with_content('WSGI') }
        it { expect(chef_run.apache_app(app)).to notify('apache2_service[compute]').to(:reload).immediately }
      end
      it { expect(chef_run.service('placement-uwsgi')).to subscribe_to('template[/etc/placement/placement.conf]').on(:restart) }
      %w(openstack-nova-api openstack-nova-metadata).each do |srv|
        it { expect(chef_run.service(srv)).to subscribe_to('delete_lines[remove dhcpbridge]').on(:restart) }
        it { expect(chef_run.service(srv)).to subscribe_to('delete_lines[remove force_dhcp_release]').on(:restart) }
        it { expect(chef_run.service(srv)).to subscribe_to('template[/etc/nova/nova.conf]').on(:restart) }
      end
      it do
        is_expected.to render_file('/etc/httpd/sites-available/placement.conf')
          .with_content(%(  ProxyPass /placement-api "unix:/run/placement/uwsgi.sock|uwsgi://localhost/" retry=0\n))
      end
      it { is_expected.to_not render_file('/etc/httpd/sites-available/nova-api.conf').with_content('/placement-api') }
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
            haproxy_tls: false,
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
          command: "nova-manage db archive_deleted_rows --max_rows 1000 --before `date --date='today - 90 days' +\\%F` --until-complete --all-cells 2>&1 | systemd-cat -t nova-rowsflush"
        )
      end
      it do
        is_expected.to create_cron_d('nova-rowspurge').with(
          minute: 20,
          hour: 6,
          user: 'nova',
          command: "nova-manage db purge --before `date --date='today - 14 days' +\\%D` --all-cells 2>&1 | systemd-cat -t nova-rowspurge"
        )
      end

      {
        'nova-fix-flavors' => 'fix-flavors.py',
        'nova-cold-migrate-host' => 'cold-migrate-host.py',
        'nova-resize-debris-check' => 'resize-debris-check.py',
        'nova-maintenance-notice' => 'maintenance-notice.py',
      }.each do |tool, script|
        it do
          is_expected.to create_cookbook_file("/usr/local/sbin/#{tool}").with(
            source: script, mode: '0750'
          )
        end
        it { is_expected.to delete_file("/root/#{tool}.py") }
      end

      it do
        is_expected.to create_remote_directory('/usr/local/share/osl-openstack/maintenance-templates').with(
          source: 'maintenance-templates',
          owner: 'root',
          group: 'root',
          mode: '0755',
          files_mode: '0644'
        )
      end
      it { is_expected.to delete_directory('/root/nova-maintenance-templates').with(recursive: true) }
      it { is_expected.to create_directory('/var/lib/osl-openstack/flavor-fixes').with(mode: '0700') }
      it { is_expected.to create_directory('/var/log/osl-openstack').with(mode: '0750') }
      it { is_expected.to_not create_directory('/root/.nova-flavor-fixes/backups') }

      context 'pci passthrough' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['fqdn'] = 'controller2.testing.osuosl.org'
          end.converge(described_recipe)
        end

        it 'is expected to render pci config' do
          is_expected.to render_file('/etc/nova/nova.conf').with_content('[pci]')
          is_expected.to render_file('/etc/nova/nova.conf').with_content('alias = { "vendor_id": "10de", "product_id": "1db5", "device_type": "type-PCI", "name": "gpu_nvidia_v100" }')
          is_expected.to_not render_file('/etc/nova/nova.conf').with_content(/^passthrough_whitelist =/)
        end
      end

      context 'region2' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['fqdn'] = 'node1.testing.osuosl.org'
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
            variables: nova_conf_vars(region2: true)
          )
        end
        # node1 has a GPU whitelisted and local storage in region2
        it 'is expected to render pci config' do
          is_expected.to render_file('/etc/nova/nova.conf').with_content('[pci]')
          is_expected.to render_file('/etc/nova/nova.conf').with_content('alias = { "vendor_id": "10de", "product_id": "1db5", "device_type": "type-PCI", "name": "gpu_nvidia_v100" }')
          is_expected.to render_file('/etc/nova/nova.conf').with_content('passthrough_whitelist = { "vendor_id": "10de", "product_id": "1db5" }')
        end
        it { is_expected.to_not render_file('/etc/nova/nova.conf').with_content('images_rbd_pool = vms') }
      end
    end
  end
end
