require_relative '../../spec_helper'

describe 'osl-openstack::dashboard' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm.dup.merge(
          step_into: %w(apache_app)
        )).converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to add_osl_repos_openstack 'dashboard' }
      it { is_expected.to create_osl_openstack_client 'dashboard' }
      it { is_expected.to accept_osl_firewall_openstack 'dashboard' }
      %w(
        osl-apache
        osl-apache::mod_wsgi
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
      it { is_expected.to install_package 'openstack-dashboard' }
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
        is_expected.to create_template('/etc/openstack-dashboard/local_settings').with(
          group: 'apache',
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
            haproxy_tls: false,
          }
        )
      end
      it do
        expect(chef_run.template('/etc/openstack-dashboard/local_settings')).to \
          notify('execute[horizon: compress]').to(:run)
      end
      it do
        expect(chef_run.template('/etc/openstack-dashboard/local_settings')).to \
          notify('apache2_service[osuosl]').to(:reload)
      end
      it do
        is_expected.to render_file('/etc/openstack-dashboard/local_settings').with_content(
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
          template: 'wsgi-horizon.conf.erb'
        )
      end
      it do
        is_expected.to render_file('/etc/httpd/sites-available/horizon.conf').with_content(
          'RewriteCond "%{HTTP_HOST}" "!^controller\.testing\.osuosl\.org" [NC]'
        )
      end
      it { expect(chef_run.apache_app('horizon')).to notify('execute[horizon: compress]').to(:run) }
      it { expect(chef_run.apache_app('horizon')).to notify('apache2_service[osuosl]').to(:reload) }
      it do
        is_expected.to nothing_execute('horizon: compress').with(
          command: <<~EOC
            /usr/bin/python3 /usr/share/openstack-dashboard/manage.py collectstatic --noinput --clear -v0
            /usr/bin/python3 /usr/share/openstack-dashboard/manage.py compress --force -v0
          EOC
        )
      end

      context 'no region set' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
        end

        include_context 'dashboard_noregion_stubs'
        it do
          is_expected.to create_template('/etc/openstack-dashboard/local_settings').with(
            group: 'apache',
            mode: '0640',
            sensitive: true,
            variables: {
              auth_url: 'controller.testing.osuosl.org',
              memcache_servers: ['controller.testing.osuosl.org:11211'],
              regions: nil,
              secret_key: '-#45g2*o=8mhe(10if%*65@g#z0r#r7m__w6kwq8s9@n%12a11',
              haproxy_tls: false,
            }
          )
        end
        it do
          is_expected.to_not render_file('/etc/openstack-dashboard/local_settings').with_content('DEFAULT_SERVICE_REGIONS')
        end
      end

      context 'HA controller' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['fqdn'] = 'controller1.testing.osuosl.org'
            node.automatic['ip6address'] = '2605:bc80:3010::140'
          end.converge(described_recipe)
        end

        include_context 'common_stubs'
        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            openstack_secrets_stub.merge(
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
        # Apache serves no IPv6 of its own in HA (the VIP does), so this
        # controller drops out of the per-host apache_http6 check even though
        # it has a public IPv6.
        it do
          expect(chef_run.node['nagios']['_http_address6']).to be_nil
        end
      end
    end
  end
end
