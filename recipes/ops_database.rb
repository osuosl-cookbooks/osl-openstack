#
# Cookbook:: osl-openstack
# Recipe:: ops_database
#
# Copyright:: 2015-2023, Oregon State University
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

osl_mysql_test "#{suffix}_keystone" do
  username s['identity']['db']['user']
  password s['identity']['db']['pass']
  encoding 'utf8'
  collation 'utf8_general_ci'
  version '10.4'
end

mariadb_server_configuration 'openstack' do
  mysqld_bind_address '0.0.0.0'
  mysqld_max_connections 1000
  mysqld_options(
    'character-set-server' => 'utf8',
    'collation-server' => 'utf8_general_ci'
  )
  notifies :restart, 'service[mariadb]', :immediately
end

service 'mariadb' do
  action :nothing
end

openstack_services.each do |service, db|
  next if service == 'messaging'

  begin
    mariadb_database "#{suffix}_#{db}" do
      password 'osl_mysql_test'
      encoding 'utf8'
      collation 'utf8_general_ci'
    end

    mariadb_user "#{s[service]['db']['user']}-localhost" do
      username s[service]['db']['user']
      ctrl_password 'osl_mysql_test'
      password s[service]['db']['pass']
      privileges [:all]
      database_name "#{suffix}_#{db}"
      action [:create, :grant]
    end

    mariadb_user s[service]['db']['user'] do
      ctrl_password 'osl_mysql_test'
      password s[service]['db']['pass']
      host '%'
      privileges [:all]
      database_name "#{suffix}_#{db}"
      action [:create, :grant]
    end
  rescue NoMethodError
    Chef::Log.warn("No databag item found for #{service}")
  end
end
