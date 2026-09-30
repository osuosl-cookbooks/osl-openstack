db_endpoint = input('db_endpoint')
controller_endpoint = input('controller_endpoint')
local_storage = input('local_storage')
nova_local_storage = input('nova_local_storage')
cinder_missing = input('cinder_missing')
# messaging_host = AMQP host (mq tier on multi-node); memcached_host =
# the memcached backend (controller1 on multi-node).
messaging_host = input('messaging_host')
messaging_port = input('messaging_port')
memcached_host = input('memcached_host')

control 'compute-controller' do
  # nova-api, nova-metadata and placement run under uWSGI behind httpd
  %w(
    openstack-nova-api
    openstack-nova-conductor
    openstack-nova-metadata
    openstack-nova-novncproxy
    openstack-nova-scheduler
    placement-uwsgi
  ).each do |s|
    describe service(s) do
      it { should be_enabled }
      it { should be_running }
    end
  end

  {
    '/run/nova/api-uwsgi.sock' => 'nova',
    '/run/nova/metadata-uwsgi.sock' => 'nova',
    '/run/placement/uwsgi.sock' => 'placement',
  }.each do |sock, user|
    describe file(sock) do
      it { should be_socket }
      its('owner') { should eq user }
      its('group') { should eq 'apache' }
    end
  end

  # nova's WSGI apps are eventlet-patched; their RabbitMQ heartbeat must run in a pthread
  %w(/etc/nova/nova-api-uwsgi.ini /etc/nova/nova-metadata-uwsgi.ini).each do |ini|
    describe file(ini) do
      its('content') { should match /^env = OS_OSLO_MESSAGING_RABBIT__HEARTBEAT_IN_PTHREAD=true$/ }
    end
  end

  describe http('http://localhost:8778/placement-api/', headers: { 'Accept' => 'application/json' }) do
    its('status') { should eq 200 }
    its('body') { should match(/"versions"/) }
  end

  %w(
    8774
    8775
    8778
  ).each do |p|
    describe port(p) do
      it { should be_listening }
      its('protocols') { should include 'tcp' }
    end
  end

  describe port(6080) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
  end

  describe ini('/etc/placement/placement.conf') do
    its('keystone_authtoken.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('keystone_authtoken.memcached_servers') { should match(/#{Regexp.escape(memcached_host)}:11211/) }
    its('keystone_authtoken.password') { should cmp 'placement' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
    its('keystone_authtoken.www_authenticate_uri') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('placement_database.connection') { should cmp "mysql+pymysql://placement_x86:placement@#{db_endpoint}:3306/placement_x86" }
  end

  describe ini('/etc/nova/nova.conf') do
    its('DEFAULT.block_device_allocate_retries') { should cmp '120' }
    its('DEFAULT.compute_monitors') { should cmp 'cpu.virt_driver' }
    its('DEFAULT.ram_allocation_ratio') { should cmp '1' }
    its('DEFAULT.disk_allocation_ratio') { should cmp '1.5' }
    its('DEFAULT.force_raw_images') { should cmp nova_local_storage ? 'false' : 'true' }
    its('DEFAULT.instance_usage_audit') { should cmp 'True' }
    its('DEFAULT.instance_usage_audit_period') { should cmp 'hour' }
    its('DEFAULT.resume_guests_state_on_host_boot') { should cmp 'True' }
    its('DEFAULT.transport_url') { should match(%r{^rabbit://openstack:openstack@#{Regexp.escape(messaging_host)}:#{messaging_port}}) }
    its('api_database.connection') { should cmp "mysql+pymysql://nova_x86:nova@#{db_endpoint}:3306/nova_api_x86" }
    its('cache.memcache_servers') { should match(/#{Regexp.escape(memcached_host)}:11211/) }
    its('database.connection') { should cmp "mysql+pymysql://nova_x86:nova@#{db_endpoint}:3306/nova_x86" }
    its('filter_scheduler.enabled_filters') { should cmp 'AggregateInstanceExtraSpecsFilter,PciPassthroughFilter,AvailabilityZoneFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter' }
    its('glance.api_servers') { should cmp "http://#{controller_endpoint}:9292" }
    its('keystone_authtoken.auth_url') { should cmp 'https://controller.testing.osuosl.org:5000/v3' }
    its('keystone_authtoken.memcached_servers') { should match(/#{Regexp.escape(memcached_host)}:11211/) }
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
      its('libvirt.live_migration_completion_timeout') { should cmp '8' }
      its('libvirt.live_migration_downtime') { should cmp '1000' }
      its('libvirt.live_migration_downtime_delay') { should cmp '3' }
      its('libvirt.live_migration_downtime_steps') { should cmp '3' }
      its('libvirt.live_migration_permit_post_copy') { should cmp 'true' }
      its('libvirt.live_migration_timeout_action') { should cmp 'force_complete' }
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

  # haproxy terminates novnc TLS in HA, so nova-novncproxy runs plain ws
  # without the local cert or --ssl_only
  if input('haproxy_tls')
    describe file('/etc/sysconfig/openstack-nova-novncproxy') do
      its('content') { should match(/^OPTIONS=""$/) }
    end
  else
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
  end

  openstack = ->(args) { %(bash -c "source /root/openrc && /usr/bin/openstack #{args}") }

  describe command(openstack.call('compute service list -f value -c Binary -c Status -c State')) do
    %w(conductor scheduler).each do |s|
      its('stdout') { should match(/nova-#{s} enabled up/) }
    end
  end

  describe command(openstack.call('catalog list -c Endpoints')) do
    its('stdout') { should match(%r{public: http://controller.testing.osuosl.org:8778}) }
    its('stdout') { should match(%r{internal: http://controller.testing.osuosl.org:8778}) }
  end

  describe command(openstack.call('--os-placement-api-version 1.2 resource class list -f value')) do
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

  describe command(openstack.call('--os-placement-api-version 1.6 trait list -f value')) do
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
    if cinder_missing
      # nova-status probes cinder because of [cinder] and finds no volumev3 endpoint
      its('stdout') { should match(/Check: Cinder API.*\n.*Result: Warning.*\n.*Details: Unable to determine Cinder API version/) }
    else
      its('stdout') { should match(/Check: Cinder API.*\n.*Result: Success/) }
    end
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
      should match /20 5 \* \* \* nova nova-manage db archive_deleted_rows --max_rows 1000 --before `date --date='today - 90 days' \+\\\%F` --until-complete --all-cells 2>&1 \| systemd-cat -t nova-rowsflush/
    end
  end
  describe file '/etc/cron.d/nova-rowspurge' do
    its('content') do
      should match /20 6 \* \* \* nova nova-manage db purge --before `date --date='today - 14 days' \+\\\%D` --all-cells 2>&1 \| systemd-cat -t nova-rowspurge/
    end
  end

  # Nova Flavor Sync script for ad-hoc RequestSpec fixes
  describe file '/root/nova-fix-flavors.py' do
    it { should be_file }
    its('mode') { should cmp '0700' }
    its('owner') { should eq 'root' }
    its('group') { should eq 'root' }
    its('content') { should match %r{^#!/opt/openstack/nova-controller/bin/python} }
    its('content') { should match /sync_specs/ }
  end

  # The helpers run on the nova-controller venv, not host python3's RDO libraries
  %w(fix-flavors cold-migrate-host resize-debris-check maintenance-notice).each do |script|
    describe command("/root/nova-#{script}.py --help") do
      its('exit_status') { should eq 0 }
    end
  end

  describe command('bash -c "source /root/openrc && /root/nova-resize-debris-check.py"') do
    its('exit_status') { should eq 0 }
  end

  describe directory '/root/.nova-flavor-fixes/backups' do
    it { should be_directory }
    its('mode') { should cmp '0700' }
    its('owner') { should eq 'root' }
    its('group') { should eq 'root' }
  end
end
