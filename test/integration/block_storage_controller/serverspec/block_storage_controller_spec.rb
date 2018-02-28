require 'serverspec'

set :backend, :exec

%w(
  openstack-cinder-api
  openstack-cinder-scheduler
).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

describe port('8776') do
  it { should be_listening.with('tcp') }
end

describe file('/etc/cinder/cinder.conf') do
  its(:content) do
    should contain(/^volume_clear_size = 256$/)
      .from(/^\[DEFAULT\]$/).to(/^\[/)
  end
  its(:content) do
    should contain(/^volume_group = openstack$/)
      .from(/^\[DEFAULT\]$/).to(/^\[/)
  end
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

describe command('source /root/openrc && sleep 60 && cinder service-list') do
  list_output = '\s*\|\sblockstoragecon.+\s*\|\snova\s\|\senabled\s\|\s*up' \
    '\s*\|\s[0-9]{4}-[0-9]{2}-[0-9]{2}'
  its(:stdout) do
    should contain(/cinder-scheduler#{list_output}/)
  end
end
