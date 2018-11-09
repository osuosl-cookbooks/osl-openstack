require 'serverspec'

set :backend, :exec

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
  it { should be_listening.with('tcp') }
end

describe file('/etc/ceilometer/ceilometer.conf') do
  its(:content) do
    should contain(/memcached_servers = .*:11211/)
      .from(/^\[keystone_authtoken\]$/).to(/^\[/)
  end
  its(:content) do
    should contain(/memcache_servers = .*:11211/)
      .from(/^\[cache\]$/).to(/^\[/)
  end
  its(:content) do
    should contain(/driver = messagingv2/)
      .from(/^\[oslo_messaging_notifications\]$/).to(/^\[/)
  end
end

[
  'meter_dispatchers = database',
].each do |s|
  describe file('/etc/ceilometer/ceilometer.conf') do
    its(:content) { should contain(/#{s}/).after(/^\[DEFAULT\]/) }
  end
end

[
  /^host = (?:[0-9]{1,3}\.){3}[0-9]{1,3}$/,
  /^default_api_return_limit = 1000000000000$/,
].each do |s|
  describe file('/etc/ceilometer/ceilometer.conf') do
    its(:content) { should contain(/#{s}/).after(/^\[api\]/) }
  end
end

describe command('source /root/openrc && ceilometer meter-list') do
  its(:stdout) { should contain(/Project ID/) }
  its(:stdout) { should_not contain(/Gone (HTTP 410) /) }
end
