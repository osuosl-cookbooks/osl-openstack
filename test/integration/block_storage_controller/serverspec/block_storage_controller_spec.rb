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
  [
    /^volume_clear_size = 256$/,
    /^volume_group = openstack$/,
    /^enable_v1_api = false$/,
    /^enable_v3_api = true$/,
  ].each do |line|
    its(:content) do
      should contain(line).from(/^\[DEFAULT\]$/).to(/^\[/)
    end
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

describe command('source /root/openrc && cinder service-list') do
  list_output = '\s*\|\s(block-storage-con|controller|allinone).+\s*\|\snova\s\|\senabled\s\|\s*up' \
    '\s*\|\s[0-9]{4}-[0-9]{2}-[0-9]{2}'
  its(:stdout) do
    should contain(/cinder-scheduler#{list_output}/)
  end
end
