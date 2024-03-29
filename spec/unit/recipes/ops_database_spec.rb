require_relative '../../spec_helper'

describe 'osl-openstack::ops_database' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'

      it do
        is_expected.to create_osl_mysql_test('keystone_x86').with(
          username: 'keystone_x86',
          password: 'keystone',
          encoding: 'utf8mb3',
          collation: 'utf8mb3_general_ci',
          version: '10.11'
        )
      end
      it do
        is_expected.to modify_mariadb_server_configuration('openstack').with(
          mysqld_bind_address: '0.0.0.0',
          mysqld_max_connections: 1000,
          mysqld_options: {
            'character-set-server' => 'utf8mb3',
            'collation-server' => 'utf8mb3_general_ci',
          }
        )
      end
      it do
        expect(chef_run.mariadb_server_configuration('openstack')).to \
          notify('service[mariadb]').to(:restart).immediately
      end
      it { is_expected.to nothing_service('mariadb') }
      {
        'ceilometer' => 'ceilometer',
        'cinder' => 'cinder',
        'glance' => 'glance',
        'heat' => 'heat',
        'horizon' => 'horizon',
        'keystone' => 'keystone',
        'neutron' => 'neutron',
        'nova' => 'nova',
        'nova_api' => 'nova',
        'nova_cell0' => 'nova',
        'placement' => 'placement',
      }.each do |db, user|
        db_name = "#{db}_x86"
        db_user = "#{user}_x86"

        it do
          is_expected.to create_mariadb_database(db_name).with(
            password: 'osl_mysql_test',
            encoding: 'utf8mb3',
            collation: 'utf8mb3_general_ci'
          )
        end
        it do
          is_expected.to create_mariadb_user("#{db_user}-#{db_name}-localhost").with(
            username: db_user,
            ctrl_password: 'osl_mysql_test',
            password: user,
            privileges: [:all],
            database_name: db_name
          )
        end
        it { is_expected.to grant_mariadb_user("#{db_user}-#{db_name}-localhost") }
        it do
          is_expected.to create_mariadb_user("#{db_user}-#{db_name}").with(
            username: db_user,
            ctrl_password: 'osl_mysql_test',
            password: user,
            host: '%',
            privileges: [:all],
            database_name: db_name
          )
        end
        it { is_expected.to grant_mariadb_user "#{db_user}-#{db_name}" }
      end
    end
  end
end
