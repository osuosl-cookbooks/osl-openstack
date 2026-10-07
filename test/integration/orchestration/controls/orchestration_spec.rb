db_endpoint = input('db_endpoint')
# messaging_host = AMQP host (mq tier on multi-node); memcached_host =
# the memcached backend (controller1 on multi-node).
messaging_host = input('messaging_host')
messaging_port = input('messaging_port')
memcached_host = input('memcached_host')

control 'orchestration' do
  describe package 'osuosl-openstack-heat' do
    it { should be_installed }
  end

  %w(
    openstack-heat-api-cfn
    openstack-heat-api
    openstack-heat-engine
  ).each do |s|
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
    end
  end

  describe file '/etc/heat/heat.conf' do
    its('owner') { should cmp 'root' }
    its('group') { should cmp 'heat' }
    its('mode') { should cmp '0640' }
  end

  describe ini('/etc/heat/heat.conf') do
    its('DEFAULT.auth_encryption_key') { should cmp '4CFk1URr4Ln37kKRNSypwjI7vv7jfLQE' }
    its('DEFAULT.heat_metadata_server_url') { should cmp 'http://controller.testing.osuosl.org:8000' }
    its('DEFAULT.heat_waitcondition_server_url') { should cmp 'http://controller.testing.osuosl.org:8000/v1/waitcondition' }
    its('DEFAULT.stack_domain_admin_password') { should cmp 'heat_domain_admin' }
    its('DEFAULT.transport_url') { should match(%r{^rabbit://openstack:openstack@#{Regexp.escape(messaging_host)}:#{messaging_port}}) }
    its('cache.memcache_servers') { should match(/#{Regexp.escape(memcached_host)}:11211/) }
    its('clients_keystone.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000' }
    its('database.connection') { should cmp "mysql+pymysql://heat_x86:heat@#{db_endpoint}:3306/heat_x86" }
    its('keystone_authtoken.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('keystone_authtoken.memcached_servers') { should match(/#{Regexp.escape(memcached_host)}:11211/) }
    its('keystone_authtoken.password') { should cmp 'heat' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
    its('keystone_authtoken.www_authenticate_uri') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
    its('trustee.auth_type') { should cmp 'v3password' }
    its('trustee.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('trustee.password') { should cmp 'heat' }
  end

  openstack = ->(args) { %(bash -c "source /root/openrc && /usr/bin/openstack #{args}") }

  describe command openstack.call('orchestration service list -c Binary -c Status -f value') do
    its('stdout') { should match(/^heat-engine up$/) }
  end
end

# The keepalived primary records each package version it synced; other controllers sync nothing
control 'orchestration-db-sync' do
  primary = input('primary_controller', value: true)
  { 'heat' => 'osuosl-openstack-heat' }.each do |svc, pkg|
    evr = command("rpm -q --qf '%{EPOCH}:%{VERSION}-%{RELEASE}' #{pkg}").stdout
    describe file("/var/lib/osl-openstack/db-sync/#{svc}") do
      if primary
        its('content') { should cmp evr }
      else
        it { should_not exist }
      end
    end
  end
end
