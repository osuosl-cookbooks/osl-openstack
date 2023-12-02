db_endpoint = input('db_endpoint')

control 'orchestration' do
  %w(
    openstack-heat-api-cfn
    openstack-heat-api
    openstack-heat-engine
  ).each do |s|
    describe package s do
      it { should be_installed }
    end

    describe service s do
      it { should be_enabled }
      it { should be_running }
    end
  end

  %w(
    8000
    8004
  ).each do |p|
    describe port(p) do
      it { should be_listening }
      its('protocols') { should include 'tcp' }
      its('addresses') { should include '0.0.0.0' }
    end
  end

  describe file '/etc/heat/heat.conf' do
    its('owner') { should cmp 'root' }
    its('group') { should cmp 'heat' }
    its('mode') { should cmp '0640' }
  end

  describe ini('/etc/heat/heat.conf') do
    its('DEFAULT.auth_encryption_key') { should cmp '4CFk1URr4Ln37kKRNSypwjI7vv7jfLQE' }
    its('DEFAULT.heat_metadata_server_url') { should cmp 'http://controller.example.com:8000' }
    its('DEFAULT.heat_waitcondition_server_url') { should cmp 'http://controller.example.com:8000/v1/waitcondition' }
    its('DEFAULT.stack_domain_admin_password') { should cmp 'heat_domain_admin' }
    its('DEFAULT.transport_url') { should cmp 'rabbit://openstack:openstack@controller.example.com:5672' }
    its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
    its('clients_keystone.auth_url') { should cmp 'https://controller.example.com:5000' }
    its('database.connection') { should cmp "mysql+pymysql://heat_x86:heat@#{db_endpoint}:3306/heat_x86" }
    its('keystone_authtoken.auth_url') { should cmp 'https://controller.example.com:5000/v3' }
    its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.password') { should cmp 'heat' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
    its('keystone_authtoken.www_authenticate_uri') { should cmp 'https://controller.example.com:5000/v3' }
    its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
    its('trustee.auth_type') { should cmp 'v3password' }
    its('trustee.auth_url') { should cmp 'https://controller.example.com:5000/v3' }
    its('trustee.password') { should cmp 'heat' }
  end

  openstack = 'bash -c "source /root/openrc && /usr/bin/openstack'

  describe command 'bash -c "source /root/openrc && /bin/heat-manage service clean"' do
    its('exit_status') { should eq 0 }
  end

  describe command "#{openstack} orchestration service list -c Binary -c Status -f value\"" do
    its('stdout') { should match(/^heat-engine up$/) }
    its('stdout') { should_not match(/^heat-engine down$/) }
  end
end
