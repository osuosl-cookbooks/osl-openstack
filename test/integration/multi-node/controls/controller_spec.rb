control 'controller' do
  %w(
    openstack-cinder-scheduler
  ).each do |s|
    describe service(s) do
      it { should be_enabled }
      it { should be_running }
    end
  end

  describe port(8776) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should_not include '127.0.0.1' }
  end

  describe ini('/etc/cinder/cinder.conf') do
    its('DEFAULT.volume_clear_size') { should cmp '256' }
    its('DEFAULT.volume_group') { should cmp 'openstack' }
    its('DEFAULT.enable_v3_api') { should cmp 'true' }
    its('DEFAULT.glance_api_version') { should_not cmp '' }
    its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
    its('DEFAULT.enabled_backends') { should cmp 'ceph,ceph_ssd' }
    its('DEFAULT.backup_driver') { should cmp 'cinder.backup.drivers.ceph' }
    its('DEFAULT.backup_ceph_conf') { should cmp '/etc/ceph/ceph.conf' }
    its('DEFAULT.backup_ceph_user') { should cmp 'cinder-backup' }
    its('DEFAULT.backup_ceph_chunk_size') { should cmp '134217728' }
    its('DEFAULT.backup_ceph_pool') { should cmp 'backups' }
    its('DEFAULT.backup_ceph_stripe_unit') { should cmp '0' }
    its('DEFAULT.backup_ceph_stripe_count') { should cmp '0' }
    its('DEFAULT.restore_discard_excess_bytes') { should cmp 'true' }
    its('ceph.volume_driver') { should cmp 'cinder.volume.drivers.rbd.RBDDriver' }
    its('ceph.volume_backend_name') { should cmp 'ceph' }
    its('ceph.rbd_pool') { should cmp 'volumes' }
    its('ceph.rbd_ceph_conf') { should cmp '/etc/ceph/ceph.conf' }
    its('ceph.rbd_flatten_volume_from_snapshot') { should cmp 'false' }
    its('ceph.rbd_max_clone_depth') { should cmp '5' }
    its('ceph.rbd_store_chunk_size') { should cmp '4' }
    its('ceph.rados_connect_timeout') { should cmp '-1' }
    its('ceph.rbd_user') { should cmp 'cinder' }
    its('ceph.rbd_secret_uuid') { should cmp 'ae3f1d03-bacd-4a90-b869-1a4fabb107f2' }
    its('libvirt.rbd_user') { should cmp 'cinder' }
    its('libvirt.rbd_secret_uuid') { should cmp 'ae3f1d03-bacd-4a90-b869-1a4fabb107f2' }
  end

  describe command('bash -c "source /root/openrc && cinder service-list"') do
    list_output = '\s*\|\s(block-storage-con|controller|allinone).+\s*\|\snova\s\|\senabled\s\|\s*up' \
      '\s*\|\s[0-9]{4}-[0-9]{2}-[0-9]{2}'
    its(:stdout) { should match(/cinder-scheduler#{list_output}/) }
  end
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
      its('addresses') { should_not include '127.0.0.1' }
    end
  end

  describe ini('/etc/nova/nova.conf') do
    its('DEFAULT.use_neutron') { should_not cmp '' }
    its('DEFAULT.disk_allocation_ratio') { should cmp '1.5' }
    its('DEFAULT.instance_usage_audit') { should cmp 'True' }
    its('DEFAULT.instance_usage_audit_period') { should cmp 'hour' }
    its('DEFAULT.resume_guests_state_on_host_boot') { should cmp 'True' }
    its('DEFAULT.block_device_allocate_retries') { should cmp '120' }
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
  %w(80 443).each do |p|
    describe port(p) do
      it { should be_listening }
      its('protocols') { should include 'tcp' }
      its('addresses') { should include '0.0.0.0' }
    end
  end

  describe file('/etc/openstack-dashboard/local_settings') do
    its('content') { should match(/'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',/) }
    its('content') { match(/'LOCATION': \[\n\s*'controller.example.com:11211',/) }
    its('content') do
      should match(/
LAUNCH_INSTANCE_DEFAULTS = {
  'create_volume': False,
}/)
    end
  end

  # Simulate logging into horizon with curl and test the output to ensure the
  # application is running correctly
  horizon_command =
    # 1. Get initial cookbooks for curl
    # 2. Grab the CSRF token
    # 3. Try logging into the site with the token
    'curl -so /dev/null -k -c c.txt -b c.txt https://localhost/auth/login/ && ' \
    'token=$(grep csrftoken c.txt | cut -f7) &&' \
    'curl -H \'Referer:https://localhost/auth/login/\' -k -c c.txt -b c.txt -d ' \
    '"login=admin&password=admin&csrfmiddlewaretoken=${token}" -v ' \
    'https://localhost/auth/login/ 2>&1'

  describe command(horizon_command) do
    its('stdout') { should match(/subject: CN=\*.example.com/) }
    its('stdout') { should match(/< HTTP.*200 OK/) }
    its('stdout') { should_not match(/CSRF verification failed. Request aborted./) }
  end
  describe yum.repo('RDO-rocky') do
    it { should exist }
    it { should be_enabled }
  end

  describe file('/root/openrc') do
    its(:content) do
      should match(%r{
export OS_USERNAME=admin
export OS_USER_DOMAIN_NAME=default
export OS_PASSWORD=admin
export OS_PROJECT_NAME=admin
export OS_PROJECT_DOMAIN_NAME=default
export OS_IDENTITY_API_VERSION=3
export OS_AUTH_URL=https://controller.example.com:5000/v3
export OS_REGION_NAME=RegionOne

# Misc options
export OS_CACERT="/etc/ssl/certs/ca-bundle.crt"
export OS_AUTH_TYPE=password})
    end
  end

  describe file('/root/openrc') do
    its(:content) { should_not match(%r{OS_AUTH_URL=http://10.1.100.*/v2.0}) }
  end

  describe file('/etc/sysconfig/iptables-config') do
    its(:content) { should match(/^IPTABLES_SAVE_ON_STOP="no"$/) }
    its(:content) { should match(/^IPTABLES_SAVE_ON_RESTART="no"$/) }
  end

  describe file('/usr/local/bin/openstack') do
    it { should_not exist }
  end

  describe command('/usr/bin/openstack -h') do
    its(:exit_status) { should eq 0 }
  end
  describe service('httpd') do
    it { should be_enabled }
    it { should be_running }
  end

  describe port(5000) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should include '0.0.0.0' }
  end

  describe port(35357) do
    it { should_not be_listening }
    its('protocols') { should_not include 'tcp' }
    its('addresses') { should_not include '0.0.0.0' }
  end

  describe command('bash -c "source /root/openrc && /usr/bin/openstack token issue"') do
    its('stdout') { should match(/expires.*[0-9]{4}-[0-9]{2}-[0-9]{2}/) }
    its('stdout') { should match(/id\s*\|\s[0-9a-z]{32}/) }
    its('stdout') { should match(/project_id\s*\|\s[0-9a-z]{32}/) }
    its('stdout') { should match(/user_id\s*\|\s[0-9a-z]{32}/) }
  end

  describe ini('/etc/keystone/keystone.conf') do
    its('memcache.servers') { should cmp 'controller.example.com:11211' }
  end

  describe apache_conf('/etc/httpd/sites-enabled/keystone-main.conf') do
    its('<VirtualHost') { should include '0.0.0.0:5000>' }
  end

  describe command('grep -q deprecation /var/log/keystone/keystone.log') do
    its('exit_status') { should eq 1 }
  end

  describe service('openstack-glance-api') do
    it { should be_enabled }
    it { should be_running }
  end

  describe service('openstack-glance-registry') do
    it { should_not be_enabled }
    it { should_not be_running }
  end

  describe port(9292) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should_not include '127.0.0.1' }
  end

  describe port(9191) do
    it { should_not be_listening }
    its('protocols') { should_not include 'tcp' }
    its('addresses') { should_not include '127.0.0.1' }
  end

  describe ini('/etc/glance/glance-api.conf') do
    its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
    its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
  end

  describe command('bash -c "source /root/openrc && /usr/bin/openstack image list"') do
    its('stdout') do
      should match(/\|\s[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\s\|\scirros.*\s\|\sactive/)
    end
  end

  describe command('bash -c "source /root/openrc && /usr/bin/openstack image show cirros -c properties -f value"') do
    its('stdout') { should match(/direct_url='rbd:/) }
    its('stdout') { should match(/locations=/) }
  end

  describe command('rbd ls images') do
    its('stdout') { should match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/) }
  end

  describe user('glance') do
    its('groups') { should include 'ceph' }
  end

  describe file('/etc/ceph/ceph.client.glance.keyring') do
    its('content') { should match(%r{key = [A-Za-z0-9+/].*==$}) }
    it { should be_owned_by 'ceph' }
    it { should be_grouped_into 'ceph' }
  end
  describe service('neutron-linuxbridge-agent') do
    it { should be_enabled }
    it { should be_running }
  end

  describe ini('/etc/neutron/plugins/ml2/linuxbridge_agent.ini') do
    its('vlans.tenant_network_type') { should cmp 'gre,vxlan' }
    its('vlans.network_vlan_ranges') { should cmp '' }
    its('vxlan.enable_vxlan') { should cmp 'true' }
    its('vxlan.l2_population') { should cmp 'true' }
    its('vxlan.local_ip') { should match(/(?:[0-9]{1,3}\.){3}[0-9]{1,3}/) }
    its('agent.polling_interval') { should cmp '2' }
    its('linux_bridge.physical_interface_mappings') { should cmp 'public:eth1.42' }
    its('securitygroup.enable_security_group') { should cmp 'True' }
    its('securitygroup.firewall_driver') { should cmp 'neutron.agent.linux.iptables_firewall.IptablesFirewallDriver' }
  end

  describe command('systemctl list-dependencies --reverse neutron-linuxbridge-agent') do
    its('stdout') { should include 'iptables' }
  end
  describe package('nagios-plugins-openstack') do
    it { should_not be_installed }
  end

  describe file('/usr/lib64/nagios/plugins/check_openstack') do
    its('content') { should match(%r{/usr/lib64/nagios/plugins/\$\{@\}}) }
    its('mode') { should cmp '0755' }
  end

  describe file('/etc/sudoers.d/nrpe-openstack') do
    its('content') do
      should match(%r{%nrpe ALL=\(root\) NOPASSWD:/usr/lib64/nagios/plugins/check_openstack})
    end
  end

  %w(
    check_cinder_api
    check_cinder_services
    check_neutron_agents
    check_neutron_floating_ip
    check_nova_hypervisors
    check_nova_images
    check_nova_services
  ).each do |check|
    describe file("/etc/nagios/nrpe.d/#{check}.cfg") do
      it { should_not exist }
    end
  end

  %w(
    check_cinder_api_v2
    check_cinder_api_v3
    check_glance_api
    check_keystone_api
    check_neutron_api
    check_neutron_floating_ip_public
    check_nova_api
  ).each do |check|
    describe command("/usr/lib64/nagios/plugins/check_nrpe -H localhost -c #{check}") do
      its('exit_status') { should eq 0 }
    end
  end

  describe file('/etc/nagios/nrpe.d/check_nova_api.cfg') do
    its('content') do
      should match(%r{command\[check_nova_api\]=/bin/sudo /usr/lib64/nagios/plugins/check_openstack check_nova_api \
--os-compute-api-version 2})
    end
  end

  describe file('/etc/nagios/nrpe.d/check_cinder_api_v2.cfg') do
    its('content') do
      should match(%r{command\[check_cinder_api_v2\]=/bin/sudo /usr/lib64/nagios/plugins/check_openstack check_cinder_api --os-volume-api-version 2$})
    end
  end

  describe file('/etc/nagios/nrpe.d/check_cinder_api_v3.cfg') do
    its('content') do
      should match(%r{command\[check_cinder_api_v3\]=/bin/sudo /usr/lib64/nagios/plugins/check_openstack check_cinder_api --os-volume-api-version 3$})
    end
  end

  describe file('/etc/nagios/nrpe.d/check_neutron_floating_ip_public.cfg') do
    its('content') do
      should match(%r{command\[check_neutron_floating_ip_public\]=/bin/sudo /usr/lib64/nagios/plugins/check_openstack check_neutron_floating_ip --ext_network_name public$})
    end
  end

  # Should match the number of VCPUs the VMs use
  t_cpu = 4

  load_thres = if %w(ppc64 ppc64le).include?(os[:arch])
                 "-w #{t_cpu * 5 + 10},#{t_cpu * 5 + 5},#{t_cpu * 5} " \
                 "-c #{t_cpu * 8 + 10},#{t_cpu * 8 + 5},#{t_cpu * 8}"
               else
                 "-w #{t_cpu * 2 + 10},#{t_cpu * 2 + 5},#{t_cpu * 2} " \
                 "-c #{t_cpu * 4 + 10},#{t_cpu * 4 + 5},#{t_cpu * 4}"
               end

  describe file('/etc/nagios/nrpe.d/check_load.cfg') do
    its('content') do
      should match(%r{command\[check_load\]=/usr/lib64/nagios/plugins/check_load #{load_thres}})
    end
  end
  %w(
    neutron-dhcp-agent
    neutron-l3-agent
    neutron-metadata-agent
    neutron-metering-agent
    neutron-server
  ).each do |s|
    describe service(s) do
      it { should be_enabled }
      it { should be_running }
    end
  end

  describe port('9696') do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should_not include '127.0.0.1' }
  end

  describe ini('/etc/neutron/neutron.conf') do
    its('DEFAULT.service_plugins') { should cmp 'neutron.services.l3_router.l3_router_plugin.L3RouterPlugin,metering' }
    its('DEFAULT.allow_overlapping_ips') { should cmp 'True' }
    its('DEFAULT.router_distributed') { should cmp 'False' }
  end

  %w(
    neutron.conf
    l3_agent.ini
    dhcp_agent.ini
  ).each do |f|
    describe ini("/etc/neutron/#{f}") do
      its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
      its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
      its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
      its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
      its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
    end
  end

  %w(l3_agent metering_agent).each do |f|
    describe ini("/etc/neutron/#{f}.ini") do
      its('DEFAULT.interface_driver') { should cmp 'neutron.agent.linux.interface.BridgeInterfaceDriver' }
    end
  end

  describe ini('/etc/neutron/dhcp_agent.ini') do
    its('DEFAULT.interface_driver') { should cmp 'neutron.agent.linux.interface.BridgeInterfaceDriver' }
    its('DEFAULT.enable_isolated_metadata') { should cmp 'True' }
    its('DEFAULT.dhcp_lease_duration') { should cmp '600' }
  end

  describe ini('/etc/neutron/metadata_agent.ini') do
    its('DEFAULT.nova_metadata_host') { should_not cmp '127.0.0.1' }
  end

  describe ini('/etc/neutron/plugin.ini') do
    its('ml2.type_drivers') { should cmp 'flat,vlan,vxlan' }
    its('ml2.extension_drivers') { should cmp 'port_security' }
    its('ml2.tenant_network_types') { should cmp 'vxlan' }
    its('ml2.mechanism_drivers') { should cmp 'linuxbridge,l2population' }
  end

  describe ini('/etc/neutron/plugin.ini') do
    its('ml2_type_flat.flat_networks') { should cmp '*' }
    its('ml2_type_vlan.network_vlan_ranges') { should cmp '' }
    its('ml2_type_gre.tunnel_id_ranges') { should cmp '32769:34000' }
    its('ml2_type_vxlan.vni_ranges') { should cmp '1:1000' }
  end

  describe command('bash -c "source /root/openrc && neutron ext-list -c alias -f value"') do
    %w(
      address-scope
      agent
      allowed-address-pairs
      auto-allocated-topology
      availability_zone
      binding
      default-subnetpools
      dhcp_agent_scheduler
      dvr
      external-net
      ext-gw-mode
      extra_dhcp_opt
      extraroute
      flavors
      l3_agent_scheduler
      l3-flavors
      l3-ha
      metering
      multi-provider
      net-mtu
      network_availability_zone
      network-ip-availability
      pagination
      port-security
      project-id
      provider
      quotas
      rbac-policies
      router
      router_availability_zone
      security-group
      service-type
      sorting
      standard-attr-description
      standard-attr-revisions
      standard-attr-timestamp
      subnet_allocation
      subnet-service-types
    ).each do |ext|
      its('stdout') { should match(/^#{ext}$/) }
    end
  end
  describe service('rabbitmq-server') do
    it { should be_enabled }
    it { should be_running }
  end

  %w(5672 15672).each do |p|
    describe port(p) do
      it { should be_listening }
      its('protocols') { should include 'tcp' }
    end
  end

  # Ensure we install the package from RDO
  describe command('rpm -qi rabbitmq-server | grep Signature') do
    its('stdout') { should match(/Key ID f9b9fee7764429e6/) }
  end

  describe command('rabbitmqctl -q list_users') do
    its('stdout') { should match(/admin.*[administrator]/) }
  end

  describe command('curl -i -u admin:admin http://localhost:15672/api/whoami') do
    its('stdout') { should match(/{"name":"admin","tags":"administrator"}/) }
  end
  %w(
    openstack-heat-api-cfn
    openstack-heat-api
    openstack-heat-engine
  ).each do |s|
    describe service(s) do
      it { should be_enabled }
      it { should be_running }
    end
  end

  describe service('openstack-heat-api-cloudwatch') do
    it { should_not be_enabled }
    it { should_not be_running }
  end

  %w(
    8000
    8004
  ).each do |p|
    describe port(p) do
      it { should be_listening }
      its('protocols') { should include 'tcp' }
      its('addresses') { should_not include '127.0.0.1' }
    end
  end

  describe port(8003) do
    it { should_not be_listening }
    its('protocols') { should_not include 'tcp' }
    its('addresses') { should_not include '127.0.0.1' }
  end

  describe ini('/etc/heat/heat.conf') do
    its('trustee.auth_plugin') { should_not cmp '' }
    its('trustee.auth_type') { should cmp 'v3password' }
    its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
  end

  describe command(
    'bash -c "source /root/openrc && /bin/heat-manage service clean && /usr/bin/openstack orchestration service list -c Binary -c Status -f value"'
  ) do
    its('stdout') { should match(/^heat-engine up$/) }
    its('stdout') { should_not match(/^heat-engine down$/) }
  end
  %w(
    openstack-ceilometer-central
    openstack-ceilometer-notification
  ).each do |s|
    describe service(s) do
      it { should be_enabled }
      it { should be_running }
    end
  end

  describe service('openstack-ceilometer-collector') do
    it { should_not be_enabled }
    it { should_not be_running }
  end

  describe port(8041) do
    it { should_not be_listening }
    its('protocols') { should_not include 'tcp' }
    its('addresses') { should_not include '127.0.0.1' }
  end

  describe port(8777) do
    it { should_not be_listening }
    its('protocols') { should_not include 'tcp' }
    its('addresses') { should_not include '127.0.0.1' }
  end

  describe ini('/etc/ceilometer/ceilometer.conf') do
    its('DEFAULT.meter_dispatchers') { should_not cmp 'database' }
    its('DEFAULT.meter_dispatchers') { should_not cmp 'gnocchi' }
    its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
  end

  describe http('http://localhost:9091/metrics', enable_remote_worker: true) do
    its('body') { should match /^image_size{instance="",job="ceilometer"/ }
  end

  describe command('bash -c "source /root/openrc && openstack server create --image cirros --flavor m1.nano test"') do
    its('exit_status') { should eq 0 }
    its('stdout') { should match /OS-EXT-STS:vm_state.*building/ }
  end

  describe command('bash -c "source /root/openrc && openstack server delete test"') do
    its('exit_status') { should eq 0 }
  end
end
