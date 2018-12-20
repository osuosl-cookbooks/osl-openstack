%w(
  openstack-ceilometer-central
  openstack-ceilometer-collector
  openstack-ceilometer-notification
).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

describe port('8777') do
  it { should be_listening }
  its('protocols') { should include 'tcp' }
  its('addresses') { should include '127.0.0.1' }
end

describe ini('/etc/ceilometer/ceilometer.conf') do
  its('DEFAULT.meter_dispatchers') { should cmp 'database' }
  its('api.default_api_return_limit') { should cmp '1000000000000' }
  its('api.host') { should cmp '127.0.0.1' }
  its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
  its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
  its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
end

describe command('bash -c "source /root/openrc && ceilometer meter-list"') do
  its('stdout') { should match(/Project ID/) }
  its('stdout') { should_not match(/Gone (HTTP 410) /) }
end
