%w(
  openstack-heat-api-cfn
  openstack-heat-api
  openstack-heat-engine
).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

describe service('openstack-heat-api-cloudwatch') do
  it { should_not be_enabled }
  it { should_not be_running }
end

%w(
  8000
  8004
).each do |p|
  describe port(p) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should include '127.0.0.1' }
  end
end

describe port(8003) do
  it { should_not be_listening }
  its('protocols') { should_not include 'tcp' }
  its('addresses') { should_not include '127.0.0.1' }
end

describe ini('/etc/heat/heat.conf') do
  its('trustee.auth_plugin') { should_not cmp '' }
  its('trustee.auth_type') { should cmp 'v3password' }
  its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
  its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
  its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
  its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
end

describe command(
  'bash -c "source /root/openrc && /bin/heat-manage service clean && /usr/bin/openstack orchestration service list -c Binary -c Status -f value"'
) do
  its('stdout') { should match(/^heat-engine up$/) }
  its('stdout') { should_not match(/^heat-engine down$/) }
end
