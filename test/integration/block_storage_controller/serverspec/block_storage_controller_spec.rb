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

[
  'notifier_strategy = messagingv2',
  'notification_driver = messaging'
].each do |s|
  describe file('/etc/cinder/cinder.conf') do
    its(:content) { should contain(/#{s}/).after(/^\[DEFAULT\]/) }
  end
end

describe command('source /root/openrc && cinder service-list') do
  list_output = '\s*\|\sblockstoragecon.+\s*\|\snova\s\|\senabled\s\|\s*up' \
    '\s*\|\s[0-9]{4}-[0-9]{2}-[0-9]{2}'
  its(:stdout) do
    should contain(/cinder-scheduler#{list_output}/)
  end
end
