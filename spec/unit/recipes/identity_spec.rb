require_relative '../../spec_helper'

describe 'osl-openstack::identity' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm.merge(
          step_into: %w(apache_app osl_openstack_openrc osl_openstack_client)
        )).converge(described_recipe)
      end

      include_context 'common_stubs'

      it_behaves_like 'restarts on package upgrade', 'osuosl-openstack-keystone', ['keystone-uwsgi']

      it_behaves_like 'db sync on upgrade', 'keystone', ['keystone: db_sync']

      it do
        is_expected.to render_file('/etc/keystone/keystone.conf')
          .with_content(/^\[database\]\nconnection = .*\n#.*\nconnection_recycle_time = 300$/)
      end

      it { is_expected.to create_osl_openstack_client('identity').with(firewall: true, openrc: true) }

      describe 'osl_openstack_client' do
        it { is_expected.to add_osl_repos_openstack('default').with(source: :osuosl, version: 'yoga') }
        it { is_expected.to_not add_osl_repos_openstack('zed') }
        it { is_expected.to_not run_execute('stage OpenStack zed') }
        it { is_expected.to upgrade_package %w(osuosl-openstack-cli osuosl-openstack-selinux) }
        it { is_expected.to create_directory('/var/lib/osl-openstack').with(recursive: true) }
        it { is_expected.to create_directory('/var/lib/osl-openstack/db-sync') }
        it { is_expected.to_not install_package('mysql') }
        it do
          is_expected.to create_file('/etc/osl-openstack/release.json').with(
            content: "#{JSON.pretty_generate('installed' => 'yoga', 'target' => 'yoga', 'staged' => true, 'node_type' => 'compute')}\n"
          )
        end
        it do
          expect(chef_run.node['osl-openstack']['release'].to_h).to eq(
            'installed' => 'yoga', 'target' => 'yoga', 'staged' => true
          )
        end
        it { is_expected.to add_dnf_automatic_policy('osl-openstack').with(exclude: %w(osuosl-openstack-*)) }
        it { is_expected.to create_osl_openstack_openrc 'identity' }
        it { is_expected.to accept_osl_firewall_openstack 'identity' }
      end

      describe 'osl_openstack_openrc' do
        it do
          is_expected.to create_template('/root/openrc').with(
            mode: '0750',
            sensitive: true,
            variables: {
              endpoint: 'controller.testing.osuosl.org',
              pass: 'admin',
              region: 'RegionOne',
            }
          )
        end
      end

      %w(
        osl-memcached
        osl-apache
        osl-apache::mod_proxy_uwsgi
        osl-apache::mod_ssl
      ).each do |r|
        it { is_expected.to include_recipe r }
      end
      it { is_expected.to upgrade_package 'osuosl-openstack-keystone' }
      it do
        is_expected.to create_certificate_manage('wildcard-identity').with(
          search_id: 'wildcard',
          cert_file: 'wildcard.pem',
          key_file: 'wildcard.key',
          chain_file: 'wildcard-bundle.crt'
        )
      end
      it do
        expect(chef_run.certificate_manage('wildcard-identity')).to \
          notify('apache2_service[osuosl]').to(:reload)
      end
      it do
        is_expected.to create_template('/etc/keystone/keystone.conf').with(
          owner: 'root',
          group: 'keystone',
          mode: '0640',
          sensitive: true,
          variables: {
            endpoint: 'controller.testing.osuosl.org',
            heartbeat_in_pthread: true,
            **messaging_vars,
            memcached_endpoint: 'controller.testing.osuosl.org:11211',
            database_connection: 'mysql+pymysql://keystone_x86:keystone@localhost:3306/keystone_x86',
          }
        )
      end
      it { expect(chef_run.template('/etc/keystone/keystone.conf')).to notify('execute[keystone: db_sync]').to(:run).immediately }
      it { expect(chef_run.template('/etc/keystone/keystone.conf')).to notify('service[keystone-uwsgi]').to(:restart) }
      # keystone is wsgi-only, so it takes the opposite value from the eventlet services
      it_behaves_like 'oslo messaging config', '/etc/keystone/keystone.conf', heartbeat_in_pthread: true
      it do
        is_expected.to nothing_execute('keystone: db_sync').with(
          command: 'keystone-manage db_sync',
          user: 'keystone',
          group: 'keystone'
        )
      end
      it do
        is_expected.to run_execute('keystone: fernet_setup').with(
          command: 'keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone',
          creates: '/etc/keystone/fernet-keys/0'
        )
      end
      it do
        is_expected.to run_execute('keystone: credential_setup').with(
          command: 'keystone-manage credential_setup --keystone-user keystone --keystone-group keystone',
          creates: '/etc/keystone/credential-keys/0'
        )
      end
      it do
        is_expected.to run_execute('keystone: bootstrap').with(
          sensitive: true,
          creates: '/etc/keystone/bootstrapped',
          command: <<~EOC
            keystone-manage bootstrap \
              --bootstrap-password admin \
              --bootstrap-username admin \
              --bootstrap-project-name admin \
              --bootstrap-role-name admin \
              --bootstrap-service-name keystone \
              --bootstrap-admin-url https://controller.testing.osuosl.org:5000/v3/ \
              --bootstrap-internal-url https://controller.testing.osuosl.org:5000/v3/ \
              --bootstrap-public-url https://controller.testing.osuosl.org:5000/v3/ \
              --bootstrap-region-id RegionOne && touch /etc/keystone/bootstrapped
            EOC
        )
      end
      it do
        is_expected.to create_template('/etc/keystone/keystone-uwsgi.ini').with(
          source: 'uwsgi.ini.erb',
          group: 'keystone',
          mode: '0640',
          variables: {
            chdir: '/opt/openstack/keystone',
            wsgi_file: '/opt/openstack/keystone/bin/keystone-wsgi-public',
            socket: '/run/keystone/uwsgi.sock',
            user: 'keystone',
            processes: 5,
            threads: 1,
            env: { 'XDG_CACHE_HOME' => '/var/cache/httpd/osuosl-keystone' },
          }
        )
      end
      it do
        is_expected.to create_directory('/var/cache/httpd/osuosl-keystone').with(owner: 'keystone', group: 'keystone', mode: '0750')
      end
      it { is_expected.to render_file('/etc/keystone/keystone-uwsgi.ini').with_content("env = XDG_CACHE_HOME=/var/cache/httpd/osuosl-keystone\n") }
      it { expect(chef_run.template('/etc/keystone/keystone-uwsgi.ini')).to notify('service[keystone-uwsgi]').to(:restart) }
      it { is_expected.to enable_service 'keystone-uwsgi' }
      it { is_expected.to start_service 'keystone-uwsgi' }
      it do
        is_expected.to create_apache_app('keystone').with(
          server_name: 'controller.testing.osuosl.org',
          server_aliases: %w(controller1.testing.osuosl.org),
          cookbook: 'osl-openstack',
          template: 'wsgi-keystone.conf.erb'
        )
      end
      it do
        is_expected.to render_file('/etc/httpd/sites-available/keystone.conf').with_content(
          'RewriteCond "%{HTTP_HOST}" "!^controller\.testing\.osuosl\.org" [NC]'
        )
      end
      it do
        is_expected.to render_file('/etc/httpd/sites-available/keystone.conf')
          .with_content('SSLEngine On')
          .with_content(%(  ProxyPass /identity "unix:/run/keystone/uwsgi.sock|uwsgi://localhost/" retry=0\n))
          .with_content(%(  ProxyPass / "unix:/run/keystone/uwsgi.sock|uwsgi://localhost/" retry=0\n))
      end
      it { is_expected.to_not render_file('/etc/httpd/sites-available/keystone.conf').with_content('WSGI') }
      it { expect(chef_run.apache_app('keystone')).to notify('apache2_service[osuosl]').to(:reload) }
      it { is_expected.to create_osl_openstack_role 'service' }
      it { is_expected.to create_osl_openstack_project('service').with(domain_name: 'default') }

      # osl_only opens :11211 to all OSL CIDRs (controllers + computes);
      # iptables rule asserted live in identity InSpec.
      it { expect(chef_run.node['osl-memcached']['default_service']).to be false }
      it { is_expected.to create_template('zzzz_default') }
      it do
        is_expected.to create_osl_memcached('memcached').with(
          port: 11211,
          osl_only: true
        )
      end

      context 'when the bag targets the next release' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.merge(step_into: %w(osl_openstack_client))).converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(openstack_secrets_stub('release' => 'zed'))
        end

        it { is_expected.to add_osl_repos_openstack('default').with(version: 'yoga') }
        it do
          is_expected.to add_osl_repos_openstack('zed').with(
            source: :osuosl, version: 'zed', repo_name: 'OSL-openstack-zed', enabled: false
          )
        end
        it do
          is_expected.to run_execute('stage OpenStack zed').with(
            command: 'dnf -y -q --setopt=keepcache=True --enablerepo=OSL-openstack-zed --downloadonly ' \
                     "upgrade 'osuosl-openstack-*' " \
                     '&& touch /var/lib/osl-openstack/staged-zed',
            creates: '/var/lib/osl-openstack/staged-zed'
          )
        end
        it { expect(chef_run.node['osl-openstack']['release']['target']).to eq 'zed' }
        it { expect(chef_run.node['osl-openstack']['release']['staged']).to be false }
      end

      context 'when the next release is not published yet' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.merge(step_into: %w(osl_openstack_client))).converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(openstack_secrets_stub('release' => 'zed'))
          stubs_for_provider('osl_openstack_client') do |provider|
            allow(provider).to receive(:openstack_release_published?).and_return(false)
          end
        end

        it { is_expected.to add_osl_repos_openstack('zed').with(enabled: false) }
        it { is_expected.to_not run_execute('stage OpenStack zed') }
      end

      {
        'in a new cloud' => [nil, 'zed'],
        'in a cloud still on yoga while the bag targets zed' => %w(yoga yoga),
      }.each do |desc, (cloud, repo)|
        context "on a new node #{desc}" do
          cached(:chef_run) do
            ChefSpec::SoloRunner.new(pltfrm.merge(step_into: %w(osl_openstack_client))).converge(described_recipe)
          end

          before do
            stub_data_bag_item('openstack', 'x86').and_return(openstack_secrets_stub('release' => 'zed'))
            stubs_for_provider('osl_openstack_client') do |provider|
              allow(provider).to receive(:openstack_release_markers).and_return([])
              allow(provider).to receive(:openstack_venv_installed?).and_return(false)
              allow(provider).to receive(:openstack_release_cloud).and_return(cloud)
            end
          end

          it { is_expected.to add_osl_repos_openstack('default').with(version: repo) }
          it { is_expected.to_not run_execute('stage OpenStack zed') }
          it do
            expect(chef_run.node['osl-openstack']['release'].to_h).to eq(
              'installed' => repo, 'target' => 'zed', 'staged' => repo == 'zed'
            )
          end
        end
      end

      context 'with a staging repo left from a finished upgrade' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.merge(step_into: %w(osl_openstack_client))).converge(described_recipe)
        end

        before do
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with('/etc/yum.repos.d/OSL-openstack-zed.repo').and_return(true)
        end

        it { is_expected.to remove_yum_repository('OSL-openstack-zed') }
        it { is_expected.to_not remove_yum_repository('OSL-openstack-yoga') }
      end

      context 'on a controller' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.merge(step_into: %w(osl_openstack_client))) do |node|
            node.override['osl-openstack']['node_type'] = 'controller'
          end.converge(described_recipe)
        end

        it { is_expected.to install_package('mysql') }
        it { expect(chef_run.node['osl-openstack']['db_node']).to be true }
        it { is_expected.to render_file('/etc/osl-openstack/release.json').with_content('"db_node": true') }
      end

      {
        'targets an older release than installed' => [%w(zed), /older than the installed zed/],
        'has mixed release markers' => [%w(yoga zed), /Mixed OpenStack release markers/],
      }.each do |desc, (markers, error)|
        context "when the node #{desc}" do
          let(:chef_run) do
            ChefSpec::SoloRunner.new(pltfrm.merge(step_into: %w(osl_openstack_client))).converge(described_recipe)
          end

          before do
            stubs_for_provider('osl_openstack_client') do |provider|
              allow(provider).to receive(:openstack_release_markers).and_return(markers)
            end
          end

          it { expect { chef_run }.to raise_error(RuntimeError, error) }
        end
      end

      context 'when the keystone package has not moved since the last sync' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
        end

        before do
          allow_any_instance_of(Chef::Resource::NotifyGroup).to receive(:openstack_db_sync_needed?).and_return(false)
        end

        it { is_expected.to_not run_notify_group('keystone: package version changed') }
      end

      context 'on a controller the ha block marks as not primary' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            openstack_secrets_stub('ha' => { 'keepalived' => { 'primary' => { 'fauxhai.local' => false } } })
          )
        end

        it { is_expected.to_not run_notify_group('keystone: package version changed') }
      end

      context 'with fernet keys in the data bag' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            openstack_secrets_stub('identity' => { 'fernet_keys' => { '0' => 'key0', '1' => 'key1' } })
          )
        end

        it { is_expected.to create_directory('/etc/keystone/fernet-keys').with(owner: 'keystone', group: 'keystone', mode: '0700') }
        %w(0 1).each do |k|
          it do
            is_expected.to create_file("/etc/keystone/fernet-keys/#{k}").with(
              content: "key#{k}", owner: 'keystone', group: 'keystone', mode: '600', sensitive: true
            )
          end
          it { expect(chef_run.file("/etc/keystone/fernet-keys/#{k}")).to notify('service[keystone-uwsgi]').to(:restart) }
        end
      end
    end
  end
end
