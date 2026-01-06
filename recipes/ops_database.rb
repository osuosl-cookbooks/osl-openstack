#
# Cookbook:: osl-openstack
# Recipe:: ops_database
#
# Copyright:: 2015-2026, Oregon State University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
s = os_secrets
suffix = s['database_server']['suffix']

osl_mysql_test "keystone_#{suffix}" do
  username "#{s['identity']['db']['user']}_#{suffix}"
  password s['identity']['db']['pass']
  encoding 'utf8mb3'
  collation 'utf8mb3_general_ci'
  version '10.11'
end

mariadb_server_configuration 'openstack' do
  mysqld_bind_address '0.0.0.0'
  mysqld_max_connections 1000
  mysqld_options(
    'character-set-server' => 'utf8mb3',
    'collation-server' => 'utf8mb3_general_ci'
  )
  notifies :restart, 'service[mariadb]', :immediately
end

service 'mariadb' do
  action :nothing
end

openstack_services.each do |service, db|
  next if service == 'messaging'

  begin
    db_user = "#{s[service]['db']['user']}_#{suffix}"
    db_name = "#{db}_#{suffix}"

    mariadb_database db_name do
      password 'osl_mysql_test'
      encoding 'utf8mb3'
      collation 'utf8mb3_general_ci'
    end

    mariadb_user "#{db_user}-#{db_name}-localhost" do
      username db_user
      ctrl_password 'osl_mysql_test'
      password s[service]['db']['pass']
      privileges [:all]
      database_name db_name
      action [:create, :grant]
    end

    mariadb_user "#{db_user}-#{db_name}" do
      username db_user
      ctrl_password 'osl_mysql_test'
      password s[service]['db']['pass']
      host '%'
      privileges [:all]
      database_name db_name
      action [:create, :grant]
    end
  rescue NoMethodError
    Chef::Log.warn("No databag item found for #{service}")
  end
end
