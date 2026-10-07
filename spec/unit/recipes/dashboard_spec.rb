require_relative '../../spec_helper'

describe 'osl-openstack::dashboard' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm.merge(
          step_into: %w(apache_app)
        )).converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to create_osl_openstack_client('dashboard').with(firewall: true, openrc: true) }
      %w(
        osl-apache
        osl-apache::mod_proxy_uwsgi
        osl-apache::mod_ssl
        osl-nrpe::check_http
      ).each do |r|
        it { is_expected.to include_recipe r }
      end
      # Off-HA the apache check_http targets node['ipaddress'] (the
      # openstack_local_api_endpoint fallback), so this override is a no-op.
      it do
        expect(chef_run.node['osl-nrpe']['check_http']['ipaddress']).to eq('10.0.0.2')
      end
      # memcached setup lives in ::identity (runs first via controller.rb).
      it { is_expected.to_not include_recipe 'osl-memcached' }
      it { is_expected.to upgrade_package 'osuosl-openstack-horizon' }
      it do
        is_expected.to create_certificate_manage('wildcard-dashboard').with(
          search_id: 'wildcard',
          cert_file: 'wildcard.pem',
          key_file: 'wildcard.key',
          chain_file: 'wildcard-bundle.crt'
        )
      end
      it do
        expect(chef_run.certificate_manage('wildcard-dashboard')).to \
          notify('apache2_service[osuosl]').to(:reload)
      end
      it { is_expected.to delete_file '/etc/httpd/conf.d/openstack-dashboard.conf' }
      it do
        expect(chef_run.file('/etc/httpd/conf.d/openstack-dashboard.conf')).to \
          notify('apache2_service[osuosl]').to(:reload)
      end
      it do
        expect(chef_run.file('/etc/httpd/conf.d/openstack-dashboard.conf')).to \
          notify('directory[purge distro conf.d]').to(:delete).immediately
      end
      it { is_expected.to delete_file '/usr/lib/systemd/system/httpd.service.d/openstack-dashboard.conf' }
      it do
        expect(chef_run.file('/usr/lib/systemd/system/httpd.service.d/openstack-dashboard.conf')).to \
          notify('execute[systemctl daemon-reload]').to(:run).immediately
      end
      it { is_expected.to nothing_execute 'systemctl daemon-reload' }
      it { is_expected.to nothing_directory('purge distro conf.d').with(path: '/etc/httpd/conf.d', recursive: true) }
      it do
        is_expected.to create_directory('/var/www/horizon/static').with(
          owner: 'horizon', group: 'apache', mode: '0755', recursive: true
        )
      end
      it do
        is_expected.to create_template('/etc/horizon/local_settings.py').with(
          source: 'local_settings.erb',
          group: 'horizon',
          mode: '0640',
          sensitive: true,
          variables: {
            auth_url: 'controller.testing.osuosl.org',
            memcache_servers: ['controller.testing.osuosl.org:11211'],
            regions: {
              'RegionOne' => 'https://controller.testing.osuosl.org:5000/v3',
              'RegionTwo' => 'https://controller.testing.osuosl.org:5000/v3',
            },
            secret_key: '-#45g2*o=8mhe(10if%*65@g#z0r#r7m__w6kwq8s9@n%12a11',
            static_root: '/var/www/horizon/static',
            haproxy_tls: false,
          }
        )
      end
      it do
        expect(chef_run.template('/etc/horizon/local_settings.py')).to \
          notify('execute[horizon: compress]').to(:run)
      end
      it do
        expect(chef_run.template('/etc/horizon/local_settings.py')).to \
          notify('service[horizon-uwsgi]').to(:restart)
      end
      it do
        is_expected.to render_file('/etc/horizon/local_settings.py')
          .with_content("STATIC_ROOT = '/var/www/horizon/static'\nSTATIC_URL = '/static/'\nCOMPRESS_OFFLINE = True\n")
      end
      it { is_expected.to_not render_file('/etc/horizon/local_settings.py').with_content('POLICY_FILES_PATH') }
      it do
        is_expected.to create_link('/opt/openstack/horizon/lib/python3.9/site-packages/openstack_dashboard/local/local_settings.py')
          .with(to: '/etc/horizon/local_settings.py')
      end
      it do
        is_expected.to create_template('/etc/horizon/horizon-uwsgi.ini').with(
          source: 'uwsgi.ini.erb',
          group: 'horizon',
          mode: '0640',
          variables: {
            chdir: '/opt/openstack/horizon/lib/python3.9/site-packages',
            wsgi_file: '/opt/openstack/horizon/lib/python3.9/site-packages/openstack_dashboard/wsgi.py',
            pythonpath: '/opt/openstack/horizon/lib/python3.9/site-packages',
            socket: '/run/horizon/uwsgi.sock',
            user: 'horizon',
            processes: 4,
            threads: 1,
            env: { 'XDG_CACHE_HOME' => '/var/cache/httpd/osuosl-horizon' },
          }
        )
      end
      it do
        is_expected.to create_directory('/var/cache/httpd/osuosl-horizon').with(owner: 'horizon', group: 'horizon', mode: '0750')
      end
      it { is_expected.to render_file('/etc/horizon/horizon-uwsgi.ini').with_content("env = XDG_CACHE_HOME=/var/cache/httpd/osuosl-horizon\n") }
      it do
        is_expected.to render_file('/etc/horizon/horizon-uwsgi.ini')
          .with_content("pythonpath = /opt/openstack/horizon/lib/python3.9/site-packages\n")
      end
      it { expect(chef_run.template('/etc/horizon/horizon-uwsgi.ini')).to notify('service[horizon-uwsgi]').to(:restart) }
      it { is_expected.to enable_service 'horizon-uwsgi' }
      it { is_expected.to start_service 'horizon-uwsgi' }
      it do
        is_expected.to render_file('/etc/horizon/local_settings.py').with_content(
        <<~EOF
          DEFAULT_SERVICE_REGIONS = [
            ('https://controller.testing.osuosl.org:5000/v3', 'RegionOne'),
            ('https://controller.testing.osuosl.org:5000/v3', 'RegionTwo'),
          ]
        EOF
      )
      end
      it do
        is_expected.to create_apache_app('horizon').with(
          cookbook: 'osl-openstack',
          server_name: 'controller.testing.osuosl.org',
          server_aliases: %w(controller1.testing.osuosl.org),
          template: 'wsgi-horizon.conf.erb',
          template_params: { haproxy_tls: false, static_root: '/var/www/horizon/static' }
        )
      end
      it do
        is_expected.to render_file('/etc/httpd/sites-available/horizon.conf')
          .with_content("  Alias /static /var/www/horizon/static\n  <Directory /var/www/horizon/static>\n")
          .with_content(%(  ProxyPass /static !\n  ProxyPass / "unix:/run/horizon/uwsgi.sock|uwsgi://localhost/" retry=0\n))
          .with_content('SSLEngine on')
      end
      it { is_expected.to_not render_file('/etc/httpd/sites-available/horizon.conf').with_content('WSGI') }
      it do
        is_expected.to render_file('/etc/httpd/sites-available/horizon.conf').with_content(
          'RewriteCond "%{HTTP_HOST}" "!^controller\.testing\.osuosl\.org" [NC]'
        )
      end
      it do
        is_expected.to render_file('/etc/httpd/sites-available/horizon.conf').with_content(
          %r{RewriteEngine On\n.*\n  RewriteRule "\^/server-status" - \[L\]\n  RewriteCond "%\{HTTP_HOST\}"}
        )
      end
      it do
        is_expected.to render_file('/etc/httpd/sites-available/horizon.conf').with_content(
          %r{<VirtualHost \*:80>\n(.*\n)*  DocumentRoot /var/www/html\n}
        )
      end
      # The default vhost's ServerName is the fqdn, so it must not sort ahead of Horizon.
      it { is_expected.to create_template('zzzz_default') }
      it { is_expected.to delete_file('/etc/httpd/sites-available/000-default.conf') }
      it { expect(chef_run.apache_app('horizon')).to notify('execute[horizon: compress]').to(:run) }
      it { expect(chef_run.apache_app('horizon')).to notify('apache2_service[osuosl]').to(:reload) }
      it do
        is_expected.to nothing_execute('horizon: compress').with(
          command: <<~EOC,
            /opt/openstack/horizon/bin/django-admin collectstatic --settings=openstack_dashboard.settings --noinput --clear -v0
            /opt/openstack/horizon/bin/django-admin compress --settings=openstack_dashboard.settings --force -v0
          EOC
          user: 'horizon',
          group: 'horizon'
        )
      end

      context 'no region set' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
        end

        include_context 'dashboard_noregion_stubs'
        it do
          is_expected.to create_template('/etc/horizon/local_settings.py').with(
            group: 'horizon',
            mode: '0640',
            sensitive: true,
            variables: {
              auth_url: 'controller.testing.osuosl.org',
              memcache_servers: ['controller.testing.osuosl.org:11211'],
              regions: nil,
              secret_key: '-#45g2*o=8mhe(10if%*65@g#z0r#r7m__w6kwq8s9@n%12a11',
              static_root: '/var/www/horizon/static',
              haproxy_tls: false,
            }
          )
        end
        it do
          is_expected.to_not render_file('/etc/horizon/local_settings.py').with_content('DEFAULT_SERVICE_REGIONS')
        end
      end

      context 'HA controller' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['fqdn'] = 'controller1.testing.osuosl.org'
            node.automatic['ip6address'] = '2605:bc80:3010::140'
          end.converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            openstack_secrets_stub(
              'ha' => {
                'api_listen_ip' => {
                  'controller1.testing.osuosl.org' => '10.1.2.3',
                },
              }
            )
          )
        end

        # The apache check_http runs locally via NRPE, so it must dial the
        # per-host backend IP apache binds in HA, not the public address.
        it do
          expect(chef_run.node['osl-nrpe']['check_http']['ipaddress']).to eq('10.1.2.3')
        end
        # Only the VIP serves IPv6 in HA, so the per-host apache_http6 check
        # drops this controller despite its public address
        it do
          expect(chef_run.node['nagios']['_http_address6']).to be_nil
        end
      end
    end
  end
end
