require 'serverspec'

set :backend, :exec

%w(
  openstack-nova-api
  openstack-nova-cert
  openstack-nova-conductor
  openstack-nova-consoleauth
  openstack-nova-metadata-api
  openstack-nova-novncproxy
  openstack-nova-scheduler
).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

%w(6080 8774 8775).each do |p|
  describe port(p) do
    it { should be_listening.with('tcp') }
  end
end

[
  'linuxnet_interface_driver = ' \
  'nova.network.linux_net.NeutronLinuxBridgeInterfaceDriver',
  'dns_server = 140.211.166.130 140.211.166.131'
].each do |s|
  describe file('/etc/nova/nova.conf') do
    its(:content) { should contain(/#{s}/).after(/^\[DEFAULT\]/) }
  end
end

describe command('source /root/openrc && openstack compute service list') do
  list_output = '\s*\|\scomputecontroll.+\s*\|\sinternal\s\|\senabled\s\|\sup' \
    '\s*\|\s[0-9]{4}-[0-9]{2}-[0-9]{2}'
  %w(conductor scheduler cert consoleauth).each do |s|
    its(:stdout) do
      should contain(/nova-#{s}#{list_output}/)
    end
  end
end
