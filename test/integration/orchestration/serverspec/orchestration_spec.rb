require 'serverspec'

set :backend, :exec

%w(
  openstack-heat-api-cfn
  openstack-heat-api-cloudwatch
  openstack-heat-api
  openstack-heat-engine
).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

%w(
  8000
  8003
  8004
).each do |p|
  describe port(p) do
    it { should be_listening.with('tcp') }
  end
end

describe file('/etc/heat/heat.conf') do
  its(:content) do
    should contain(/memcached_servers = .*:11211/).from(/^\[keystone_authtoken\]$/).to(/^\[/)
  end
  its(:content) do
    should contain(/memcache_servers = .*:11211/).from(/^\[cache\]$/).to(/^\[/)
  end
  its(:content) do
    should contain(/driver = messagingv2/).from(/^\[oslo_messaging_notifications\]$/).to(/^\[/)
  end
end

describe command(
  'source /root/openrc && /usr/local/bin/openstack orchestration service list -c binary -c status -f value'
) do
  its(:stdout) { should match(/^heat-engine up$/) }
  its(:stdout) { should_not match(/^heat-engine down$/) }
end
