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

describe command('source /root/openrc && /usr/local/bin/openstack image list') do
  its(:stdout) do
    should contain(/\|\s[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}\
-[0-9a-f]{12}\s\|\scirros\s\|\sactive/)
  end
end

describe file('/var/lib/glance/images') do
  it { should be_mounted.with(type: 'fuse.glusterfs') }
end
