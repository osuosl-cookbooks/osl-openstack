db_endpoint = input('db_endpoint')
controller_endpoint = input('controller_endpoint')
local_storage = input('local_storage')

control 'compute-controller' do
  %w(
    openstack-nova-conductor
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

  %w(
    8774
    8775
    8778
  ).each do |p|
    describe port(p) do
      it { should be_listening }
      its('protocols') { should include 'tcp' }
      its('addresses') { should include '0.0.0.0' }
    end
  end

  describe port(6080) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should include '0.0.0.0' }
  end

  describe ini('/usr/share/nova/nova-dist.conf') do
    its('DEFAULT.dhcpbridge') { should cmp nil }
    its('DEFAULT.dhcpbridge_flagfile') { should cmp nil }
    its('DEFAULT.force_dhcp_release') { should cmp nil }
  end

  describe ini('/etc/placement/placement.conf') do
    its('keystone_authtoken.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('keystone_authtoken.memcached_servers') { should cmp "#{controller_endpoint}:11211" }
    its('keystone_authtoken.password') { should cmp 'placement' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
    its('keystone_authtoken.www_authenticate_uri') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('placement_database.connection') { should cmp "mysql+pymysql://placement_x86:placement@#{db_endpoint}:3306/placement_x86" }
  end

  describe ini('/etc/nova/nova.conf') do
    its('DEFAULT.block_device_allocate_retries') { should cmp '120' }
    its('DEFAULT.compute_monitors') { should cmp 'cpu.virt_driver' }
    its('DEFAULT.cpu_allocation_ratio') { should_not cmp '' }
    its('DEFAULT.ram_allocation_ratio') { should cmp '1' }
    its('DEFAULT.disk_allocation_ratio') { should cmp '1.5' }
    its('DEFAULT.force_raw_images') { should cmp 'true' }
    its('DEFAULT.instance_usage_audit') { should cmp 'True' }
    its('DEFAULT.instance_usage_audit_period') { should cmp 'hour' }
    its('DEFAULT.resume_guests_state_on_host_boot') { should cmp 'True' }
    its('DEFAULT.transport_url') { should cmp "rabbit://openstack:openstack@#{controller_endpoint}:5672" }
    its('DEFAULT.use_neutron') { should_not cmp '' }
    its('api_database.connection') { should cmp "mysql+pymysql://nova_x86:nova@#{db_endpoint}:3306/nova_api_x86" }
    its('cache.memcache_servers') { should cmp "#{controller_endpoint}:11211" }
    its('database.connection') { should cmp "mysql+pymysql://nova_x86:nova@#{db_endpoint}:3306/nova_x86" }
    its('filter_scheduler.enabled_filters') { should cmp 'AggregateInstanceExtraSpecsFilter,PciPassthroughFilter,AvailabilityZoneFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter' }
    its('glance.api_servers') { should cmp "http://#{controller_endpoint}:9292" }
    its('keystone_authtoken.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('keystone_authtoken.memcached_servers') { should cmp "#{controller_endpoint}:11211" }
    its('keystone_authtoken.password') { should cmp 'nova' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
    its('keystone_authtoken.www_authenticate_uri') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('libvirt.cpu_model_extra_flags') { should cmp 'VMX' }
    unless local_storage
      its('libvirt.disk_cachemodes') { should cmp 'network=writeback' }
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
    its('neutron.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('neutron.metadata_proxy_shared_secret') { should cmp '2SJh0RuO67KpZ63z' }
    its('neutron.password') { should cmp 'neutron' }
    its('notifications.notify_on_state_change') { should cmp 'vm_and_task_state' }
    its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
    its('placement.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('placement.password') { should cmp 'placement' }
    its('serial_console.base_url') { should cmp "ws://#{controller_endpoint}:6083" }
    its('service_user.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('service_user.password') { should cmp 'nova' }
    its('vnc.novncproxy_base_url') { should cmp "https://#{controller_endpoint}:6080/vnc_auto.html" }
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
    its('content') { should match %r{OPTIONS="--ssl_only --cert /etc/nova/pki/certs/novnc.pem --key /etc/nova/pki/private/novnc.key"} }
  end

  openstack = 'bash -c "source /root/openrc && /usr/bin/openstack'

  describe command("#{openstack} compute service list -f value -c Binary -c Status -c State\"") do
    %w(conductor scheduler).each do |s|
      its('stdout') { should match(/nova-#{s} enabled up/) }
    end
  end

  describe command("#{openstack} catalog list -c Endpoints\"") do
    its('stdout') { should match(%r{public: http://controller.testing.osuosl.org:8778}) }
    its('stdout') { should match(%r{internal: http://controller.testing.osuosl.org:8778}) }
  end

  describe command("#{openstack} --os-placement-api-version 1.2 resource class list -f value\"") do
    %w(
      DISK_GB
      IPV4_ADDRESS
      MEMORY_MB
      NET_BW_EGR_KILOBIT_PER_SEC
      NET_BW_IGR_KILOBIT_PER_SEC
      NUMA_CORE
      NUMA_MEMORY_MB
      NUMA_SOCKET
      NUMA_THREAD
      PCI_DEVICE
      PCPU
      SRIOV_NET_VF
      VCPU
      VGPU
      VGPU_DISPLAY_HEAD
    ).each do |r|
      its('stdout') { should match /^#{r}$/ }
    end
  end

  describe command("#{openstack} --os-placement-api-version 1.6 trait list -f value\"") do
    %w(
      HW_CPU_AARCH64_AES
      HW_CPU_X86_AVX2
      HW_GPU_CUDA_COMPUTE_CAPABILITY_V7_2
      HW_NIC_SRIOV
      STORAGE_DISK_HDD
    ).each do |r|
      its('stdout') { should match /^#{r}$/ }
    end
  end

  describe command('bash -c "source /root/openrc && /bin/placement-status upgrade check"') do
    its('stdout') { should match(/Check: Incomplete Consumers.*\n.*Result: Success/) }
    its('stdout') { should match(/Check: Missing Root Provider IDs.*\n.*Result: Success/) }
  end

  describe command('bash -c "source /root/openrc && /bin/nova-status upgrade check"') do
    its('stdout') { should match(/Check: Cells v2.*\n.*Result: Success/) }
    its('stdout') { should match(/Check: Cinder API.*\n.*Result: Success/) }
    its('stdout') { should match(/Check: hw_machine_type unset.*\n.*Result: Success/) }
    its('stdout') { should match(/Check: Older than N-1 computes.*\n.*Result: Success/) }
    its('stdout') { should match(/Check: Placement API.*\n.*Result: Success/) }
    its('stdout') { should match(/Check: Policy File JSON to YAML Migration.*\n.*Result: Success/) }
    its('stdout') { should match(/Check: Policy Scope-based Defaults.*\n.*Result: Success/) }
  end

  describe http('https://controller.testing.osuosl.org:6080', ssl_verify: false) do
    its('status') { should cmp 200 }
  end

  describe file '/etc/cron.d/nova-rowsflush' do
    its('content') do
      should match %r{20 5 \* \* \* nova nova-manage db archive_deleted_rows --max_rows 1000 --before `date --date='today - 90 days' \+\\\%F` --until-complete --all-cells >>/var/log/nova/nova-rowsflush.log 2>&1}
    end
  end
  describe file '/etc/cron.d/nova-rowspurge' do
    its('content') do
      should match %r{20 6 \* \* \* nova nova-manage db purge --before `date --date='today - 14 days' \+\\\%D` --all-cells >>/var/log/nova/nova-rowspurge.log 2>&1}
    end
  end

  # Nova Flavor Sync script for ad-hoc RequestSpec fixes
  describe file '/root/nova-fix-flavors.py' do
    it { should be_file }
    its('mode') { should cmp '0700' }
    its('owner') { should eq 'root' }
    its('group') { should eq 'root' }
    its('content') { should match %r{^#!/usr/bin/env python3} }
    its('content') { should match /sync_specs/ }
  end

  describe directory '/root/.nova-flavor-fixes/backups' do
    it { should be_directory }
    its('mode') { should cmp '0700' }
    its('owner') { should eq 'root' }
    its('group') { should eq 'root' }
  end
end
