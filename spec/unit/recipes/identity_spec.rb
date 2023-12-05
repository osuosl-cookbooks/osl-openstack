require_relative '../../spec_helper'

describe 'osl-openstack::identity' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm.dup.merge(
          step_into: %w(osl_openstack_openrc osl_openstack_client)
        )).converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to add_osl_repos_openstack 'identity' }
      it { is_expected.to create_osl_openstack_client 'identity' }
      it { is_expected.to accept_osl_firewall_openstack 'identity' }
      it { is_expected.to create_osl_openstack_openrc 'identity' }

      describe 'osl_openstack_openrc' do
        it { is_expected.to add_osl_repos_openstack 'default' }
        it do
          is_expected.to install_package(
            %w(
              python
              python-devel
              python-libs
              tkinter
              yum-plugin-versionlock
            )
          )
        end
        it { is_expected.to run_execute 'downgrade to python-2.7.5-93.el7_9' }
        it { is_expected.to install_package 'python-openstackclient' }

        context 'versionlock set' do
          cached(:chef_run) do
            ChefSpec::SoloRunner.new(pltfrm.dup.merge(
              step_into: %w(osl_openstack_client)
            )).converge(described_recipe)
          end

          before do
            allow(File).to receive(:readlines).and_call_original
            allow(File).to receive(:readlines).with('/etc/yum/pluginconf.d/versionlock.list').and_return(%w(python))
          end

          it { is_expected.to nothing_execute 'downgrade to python-2.7.5-93.el7_9' }
        end
      end

      describe 'osl_openstack_openrc' do
        it do
          is_expected.to create_template('/root/openrc').with(
            mode: '0750',
            sensitive: true,
            variables: {
              endpoint: 'controller.example.com',
              pass: 'admin',
            }
          )
        end
      end

      %w(
        certificate::wildcard
        osl-memcached
        osl-apache
        osl-apache::mod_wsgi
        osl-apache::mod_ssl
      ).each do |r|
        it { is_expected.to include_recipe r }
      end
      it { is_expected.to install_package 'openstack-keystone' }
      it do
        is_expected.to create_template('/etc/keystone/keystone.conf').with(
          owner: 'root',
          group: 'keystone',
          mode: '0640',
          sensitive: true,
          variables: {
              endpoint: 'controller.example.com',
              transport_url: 'rabbit://openstack:openstack@controller.example.com:5672',
              memcached_endpoint: 'controller.example.com:11211',
              database_connection: 'mysql+pymysql://keystone_x86:keystone@localhost:3306/keystone_x86',
          }
        )
      end
      it { expect(chef_run.template('/etc/keystone/keystone.conf')).to notify('execute[keystone: db_sync]').to(:run).immediately }
      it { expect(chef_run.template('/etc/keystone/keystone.conf')).to notify('apache2_service[osuosl]').to(:reload) }
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
              --bootstrap-admin-url https://controller.example.com:5000/v3/ \
              --bootstrap-internal-url https://controller.example.com:5000/v3/ \
              --bootstrap-public-url https://controller.example.com:5000/v3/ \
              --bootstrap-region-id RegionOne && touch /etc/keystone/bootstrapped
            EOC
        )
      end
      it do
        is_expected.to create_apache_app('keystone').with(
          server_name: 'controller.example.com',
          server_aliases: [],
          cookbook: 'osl-openstack',
          template: 'wsgi-keystone.conf.erb'
        )
      end
      it { expect(chef_run.apache_app('keystone')).to notify('apache2_service[osuosl]').to(:reload) }
      it { is_expected.to create_osl_openstack_role 'service' }
      it { is_expected.to create_osl_openstack_project('service').with(domain_name: 'default') }
    end
  end
end
