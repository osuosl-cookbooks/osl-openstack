require 'serverspec'

set :backend, :exec

%w(
  openstack-ceilometer-api
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

[
  'meter_dispatchers = database',
  'memcached_servers = .*:11211'
].each do |s|
  describe file('/etc/ceilometer/ceilometer.conf') do
    its(:content) { should contain(/#{s}/).after(/^\[DEFAULT\]/) }
  end
end

describe command('source /root/openrc && ceilometer meter-list') do
  its(:stdout) { should contain(/Project ID/) }
  its(:stdout) { should_not contain(/Gone (HTTP 410) /) }
end
