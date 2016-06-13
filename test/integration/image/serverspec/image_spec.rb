require 'serverspec'

set :backend, :exec

%w(openstack-glance-api openstack-glance-registry).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

%w(9292 9191).each do |p|
  describe port(p) do
    it { should be_listening.with('tcp') }
  end
end

describe file('/etc/glance/glance-api.conf') do
  its(:content) { should contain(/memcached_servers = .*:11211/) }
  its(:content) { should contain(/notifier_strategy = messagingv2/) }
  its(:content) { should contain(/notification_driver = messaging/) }
end

describe command('source /root/openrc && openstack image list') do
  its(:stdout) do
    should contain(/\|\s[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}\
-[0-9a-f]{12}\s\|\scirros\s\|\sactive/)
  end
end
