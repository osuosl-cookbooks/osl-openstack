require_relative '../../spec_helper'

describe 'osl-openstack::ops_database' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm) do |node|
          node.normal['osl-openstack']['cluster_name'] = 'x86'
        end.converge(described_recipe)
      end

      include_context 'common_stubs'

      it do
        is_expected.to create_osl_mysql_test('x86_keystone').with(
          username: 'keystone',
          password: 'keystone',
          encoding: 'utf8',
          collation: 'utf8_general_ci',
          version: '10.4'
        )
      end
      it do
        is_expected.to modify_mariadb_server_configuration('openstack').with(
          mysqld_bind_address: '0.0.0.0',
          mysqld_max_connections: 1000,
          mysqld_options: {
            'character-set-server' => 'utf8',
            'collation-server' => 'utf8_general_ci',
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
        it do
          is_expected.to create_mariadb_database("x86_#{db}").with(
            password: 'osl_mysql_test',
            encoding: 'utf8',
            collation: 'utf8_general_ci'
          )
        end
        it do
          is_expected.to create_mariadb_user("#{user}-localhost").with(
            username: user,
            ctrl_password: 'osl_mysql_test',
            password: user,
            privileges: [:all],
            database_name: "x86_#{user}"
          )
        end
        it { is_expected.to grant_mariadb_user("#{user}-localhost") }
        it do
          is_expected.to create_mariadb_user(user).with(
            ctrl_password: 'osl_mysql_test',
            password: user,
            host: '%',
            privileges: [:all],
            database_name: "x86_#{user}"
          )
        end
        it { is_expected.to grant_mariadb_user user }
      end
    end
  end
end
