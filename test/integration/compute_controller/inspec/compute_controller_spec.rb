%w(
  openstack-nova-conductor
  openstack-nova-consoleauth
  openstack-nova-novncproxy
  openstack-nova-scheduler
).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

# These are on httpd now via wsgi
%w(
  openstack-nova-api
  openstack-nova-metadata-api
).each do |s|
  describe service(s) do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

%w(6080 8774 8775).each do |p|
  describe port(p) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should include '127.0.0.1' }
  end
end

describe ini('/usr/share/nova/nova-dist.conf') do
  its('DEFAULT.dhcpbridge') { should cmp nil }
  its('DEFAULT.dhcpbridge_flagfile') { should cmp nil }
  its('DEFAULT.force_dhcp_release') { should cmp nil }
end

describe ini('/etc/nova/nova.conf') do
  its('DEFAULT.use_neutron') { should_not cmp '' }
  its('DEFAULT.disk_allocation_ratio') { should cmp '1.5' }
  its('DEFAULT.instance_usage_audit') { should cmp 'True' }
  its('DEFAULT.instance_usage_audit_period') { should cmp 'hour' }
  its('DEFAULT.resume_guests_state_on_host_boot') { should cmp 'True' }
  its('DEFAULT.block_device_allocate_retries') { should cmp '120' }
  its('DEFAULT.compute_monitors') { should cmp 'cpu.virt_driver' }
  its('notifications.notify_on_state_change') { should cmp 'vm_and_task_state' }
  its('filter_scheduler.enabled_filters') do
    should cmp 'AggregateInstanceExtraSpecsFilter,RetryFilter,AvailabilityZoneFilter,RamFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter'
  end
  its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
  its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
  its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
  its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
  its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
  its('libvirt.disk_cachemodes') { should cmp 'network=writeback' }
  its('libvirt.force_raw_images') { should cmp 'true' }
  its('libvirt.hw_disk_discard') { should cmp 'unmap' }
  its('libvirt.images_rbd_ceph_conf') { should cmp '/etc/ceph/ceph.conf' }
  its('libvirt.images_rbd_pool') { should cmp 'vms' }
  its('libvirt.images_type') { should cmp 'rbd' }
  its('libvirt.inject_key') { should cmp 'false' }
  its('libvirt.inject_partition') { should cmp '-2' }
  its('libvirt.inject_password') { should cmp 'false' }
  its('libvirt.live_migration_flag') { should cmp 'VIR_MIGRATE_UNDEFINE_SOURCE,VIR_MIGRATE_PEER2PEER,VIR_MIGRATE_LIVE,VIR_MIGRATE_PERSIST_DEST,VIR_MIGRATE_TUNNELLED' }
  its('libvirt.rbd_secret_uuid') { should cmp 'ae3f1d03-bacd-4a90-b869-1a4fabb107f2' }
  its('libvirt.rbd_user') { should cmp 'cinder' }
end

%w(
  /etc/nova/pki/certs/novnc.pem
  /etc/nova/pki/private/novnc.key
).each do |c|
  describe file(c) do
    it { should be_owned_by 'nova' }
    its('group') { should include 'nova' }
  end
end

describe file('/etc/sysconfig/openstack-nova-novncproxy') do
  its('content') { should match(%r{cert.*/etc/nova/pki}) }
end

openstack = 'bash -c "source /root/openrc && /usr/bin/openstack'

describe command("#{openstack} compute service list -f value -c Binary -c Status -c State\"") do
  %w(conductor scheduler consoleauth).each do |s|
    its('stdout') { should match(/nova-#{s} enabled up/) }
  end
end

describe command("#{openstack} catalog list -c Endpoints -f value\"") do
  its('stdout') { should match(%r{public: http://controller.example.com:8778}) }
  its('stdout') { should match(%r{internal: http://controller.example.com:8778}) }
end

describe command('bash -c "source /root/openrc && /bin/nova-status upgrade check"') do
  its('stdout') { should match(/Check: Cells v2.*\n.*Result: Success/) }
  its('stdout') { should match(/Check: Placement API.*\n.*Result: Success/) }
  its('stdout') { should match(/Check: Resource Providers.*\n.*Result: Success/) }
end

describe http('https://controller.example.com:6080', enable_remote_worker: true, ssl_verify: false) do
  its('status') { should cmp 200 }
end
