require 'serverspec'

set :backend, :exec

%w(
  openstack-nova-api
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
  'linuxnet_interface_driver = nova.network.linux_net.NeutronLinuxBridgeInterfaceDriver',
  'dns_server = 140.211.166.130 140.211.166.131',
  'disk_allocation_ratio = 1.5',
  'instance_usage_audit = True',
  'instance_usage_audit_period = hour',
  'resume_guests_state_on_host_boot = True',
  'block_device_allocate_retries = 120',
].each do |s|
  describe file('/etc/nova/nova.conf') do
    its(:content) do
      should contain(/#{s}/).from(/^\[DEFAULT\]/).to(/^\[/)
    end
  end
end

describe file('/etc/nova/nova.conf') do
  its(:content) do
    should contain(/^enabled_filters = AggregateInstanceExtraSpecsFilter,AvailabilityZoneFilter,RamFilter,ComputeFilter$/)
      .from(/^\[filter_scheduler\]/).to(/^\[/)
  end
  its(:content) do
    should_not contain(/^use_neutron =/)
      .from(/^\[DEFAULT\]/).to(/^\[/)
  end
  its(:content) do
    should contain(/^notify_on_state_change = vm_and_task_state$/)
      .from(/^\[notifications\]/).to(/^\[/)
  end
  its(:content) do
    should contain(/memcached_servers = .*:11211/)
      .from(/^\[keystone_authtoken\]/).to(/^\[/)
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

%w(
  /etc/nova/pki/certs/novnc.pem
  /etc/nova/pki/private/novnc.key
).each do |c|
  describe file(c) do
    it { should be_owned_by 'nova' }
    it { should be_grouped_into 'nova' }
  end
end

# describe file('/etc/sysconfig/openstack-nova-novncproxy') do
#   its(:content) do
#     should contain(%r{cert.*/etc/nova/pki})
#   end
# end

openstack = 'source /root/openrc && /usr/local/bin/openstack'

describe command("#{openstack} compute service list -f value -c Binary -c Status -c State") do
  %w(conductor scheduler consoleauth).each do |s|
    its(:stdout) { should contain(/nova-#{s} enabled up/) }
  end
end

describe command("#{openstack} catalog list -c Endpoints -f value") do
  its(:stdout) do
    should match(%r{public: http://controller.example.com:8778})
  end
  its(:stdout) do
    should match(%r{internal: http://controller.example.com:8778})
  end
end

describe command('source /root/openrc && /bin/nova-status upgrade check') do
  its(:stdout) { should match(/Check: Cells v2.*\n.*Result: Success/) }
  its(:stdout) { should match(/Check: Placement API.*\n.*Result: Success/) }
  its(:stdout) { should match(/Check: Resource Providers.*\n.*Result: Success/) }
end

describe command('curl -k -v https://controller.example.com:6080 2>&1') do
  its(:stdout) { should contain(/SSL connection/) }
  its(:stdout) { should contain(/HTTP.*200 OK/) }
end
