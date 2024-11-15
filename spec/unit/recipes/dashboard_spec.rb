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
        osl-memcached
        osl-apache
        osl-apache::mod_wsgi
        osl-apache::mod_ssl
      ).each do |r|
        it { is_expected.to include_recipe r }
      end
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
            auth_url: 'controller.example.com',
            memcache_servers: 'controller.example.com:11211',
            regions: {
              'RegionOne' => 'https://controller.example.com:5000/v3',
              'RegionTwo' => 'https://controller.example.com:5000/v3',
            },
            secret_key: '-#45g2*o=8mhe(10if%*65@g#z0r#r7m__w6kwq8s9@n%12a11',
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
            ('https://controller.example.com:5000/v3', 'RegionOne'),
            ('https://controller.example.com:5000/v3', 'RegionTwo'),
          ]
        EOF
      )
      end
      it do
        is_expected.to create_apache_app('horizon').with(
          cookbook: 'osl-openstack',
          server_name: 'controller.example.com',
          server_aliases: %w(controller1.example.com),
          template: 'wsgi-horizon.conf.erb'
        )
      end
      it do
        is_expected.to render_file('/etc/httpd/sites-available/horizon.conf').with_content(
          'RewriteCond "%{HTTP_HOST}" "!^controller\.example\.com" [NC]'
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
              auth_url: 'controller.example.com',
              memcache_servers: 'controller.example.com:11211',
              regions: nil,
              secret_key: '-#45g2*o=8mhe(10if%*65@g#z0r#r7m__w6kwq8s9@n%12a11',
            }
          )
        end
        it do
          is_expected.to_not render_file('/etc/openstack-dashboard/local_settings').with_content('DEFAULT_SERVICE_REGIONS')
        end
      end
    end
  end
end
