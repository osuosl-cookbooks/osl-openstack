%w(
  openstack-ceilometer-central
  openstack-ceilometer-notification
).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

describe service('openstack-ceilometer-collector') do
  it { should_not be_enabled }
  it { should_not be_running }
end

describe port(8041) do
  it { should_not be_listening }
  its('protocols') { should_not include 'tcp' }
  its('addresses') { should_not include '127.0.0.1' }
end

describe port(8777) do
  it { should_not be_listening }
  its('protocols') { should_not include 'tcp' }
  its('addresses') { should_not include '127.0.0.1' }
end

describe ini('/etc/ceilometer/ceilometer.conf') do
  its('DEFAULT.meter_dispatchers') { should_not cmp 'database' }
  its('DEFAULT.meter_dispatchers') { should_not cmp 'gnocchi' }
  its('api.default_api_return_limit') { should_not cmp '1000000000000' }
  its('api.host') { should cmp '127.0.0.1' }
  its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
  its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
  its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
  its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
end

describe http('http://localhost:9091/metrics', enable_remote_worker: true) do
  its('body') { should match /^image_size{instance="",job="ceilometer"/ }
end
