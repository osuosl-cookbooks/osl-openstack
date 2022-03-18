control 'compute' do
  describe ini('/etc/nova/nova.conf') do
    its('DEFAULT.use_neutron') { should_not cmp '' }
    its('DEFAULT.disk_allocation_ratio') { should cmp '1.5' }
    its('DEFAULT.instance_usage_audit') { should cmp 'True' }
    its('DEFAULT.instance_usage_audit_period') { should cmp 'hour' }
    its('DEFAULT.resume_guests_state_on_host_boot') { should cmp 'True' }
    its('DEFAULT.block_device_allocate_retries') { should cmp '120' }
    its('notifications.notify_on_state_change') { should cmp 'vm_and_task_state' }
    its('filter_scheduler.enabled_filters') do
      should cmp 'AggregateInstanceExtraSpecsFilter,PciPassthroughFilter,AvailabilityZoneFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter'
    end
    its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
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

  describe http('https://controller.example.com:6080', ssl_verify: false) do
    its('status') { should cmp 200 }
  end
  %w(
    openstack-nova-compute
    openstack-ceilometer-compute
    libvirt-guests
  ).each do |s|
    describe service(s) do
      it { should be_enabled }
      it { should be_running }
    end
  end

  describe kernel_module('tun') do
    it { should be_loaded }
  end

  %w(/var/run/ceph/guests /var/log/ceph).each do |d|
    describe file(d) do
      its('owner') { should eq 'qemu' }
      its('group') { should include 'libvirt' }
      its('type') { should eq :directory }
    end
  end

  %w(nova cinder qemu).each do |u|
    describe user(u) do
      its('groups') { should include 'ceph' }
    end
  end

  %w(cinder cinder-backup).each do |key|
    describe file("/etc/ceph/ceph.client.#{key}.keyring") do
      its('owner') { should eq 'ceph' }
      its('group') { should include 'ceph' }
      its('content') { should match(%r{key = [A-Za-z0-9+/].*==$}) }
    end
  end

  openstack = 'bash -c "source /root/openrc && /usr/bin/openstack'

  describe command("#{openstack} compute service list -f value -c Binary -c Status -c State\"") do
    its('stdout') { should match(/nova-compute enabled up/) }
  end

  describe command('virsh secret-list') do
    its('stdout') do
      should match(/ae3f1d03-bacd-4a90-b869-1a4fabb107f2\s.+ceph client.cinder secret/)
    end
  end

  describe command('virsh secret-get-value ae3f1d03-bacd-4a90-b869-1a4fabb107f2') do
    its('stdout') { should match(/^[A-Za-z0-9+].*==$/) }
  end

  describe file('/tmp/kitchen/cache/secret.xml') do
    it { should_not exist }
  end

  describe file('/etc/sysconfig/libvirt-guests') do
    its('content') { should match(/^ON_BOOT=ignore$/) }
    its('content') { should match(/^ON_SHUTDOWN=shutdown$/) }
    its('content') { should match(/^PARALLEL_SHUTDOWN=25$/) }
    its('content') { should match(/^SHUTDOWN_TIMEOUT=120$/) }
  end

  describe file('/var/lib/nova/.ssh/authorized_keys') do
    its('content') do
      should match(%r{^ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDYOuLkP1F/Sm/dCJAA7k\
me\+ObO4J8x2HrZU40W8QqW4yFqRPKnW5HYLeUpRzIFzWen/LIn6R6lxTfSAnnD8qEEuKbFjH5WRqJY\
CJeAyaTBTRyU1FHlcTR/EQ/HVZ38TQwCztZgboFb5zmWqYc3/BYBHGA6XeYN5jRcHvZbyaGL\+YA1/K\
PIjpbQfqIPXdHfodoSNX4qQQccYBq2c/rq3Puh7Q9oVph6a2lq0wWsqYyq0vTGHPKFYShVpwDl2Z3c8\
eB3P7yFRzOR2VNuezJlOgoHz6D/mBObLj1n\+yi07bcGbpwAH/rLEyiy4gVdru2qQAcbDL9Yibk96lo\
vim/IH4dV nova-migration$})
    end
    its('mode') { should cmp '00600' }
    it { should be_owned_by 'nova' }
    it { should be_grouped_into 'nova' }
  end

  describe file('/var/lib/nova/.ssh/id_rsa') do
    its('content') do
      should match(%r{^-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA2Dri5D9Rf0pv3QiQAO5JnvjmzuCfMdh62VONFvEKluMhakTy
p1uR2C3lKUcyBc1np/yyJ\+kepcU30gJ5w/KhBLimxYx\+VkaiWAiXgMmkwU0clNRR
5XE0fxEPx1Wd/E0MAs7WYG6BW\+c5lqmHN/wWARxgOl3mDeY0XB72W8mhi/mANfyj
yI6W0H6iD13R36HaEjV\+KkEHHGAatnP66tz7oe0PaFaYemtpatMFrKmMqtL0xhzy
hWEoVacA5dmd3PHgdz\+8hUczkdlTbnsyZToKB8\+g/5gTmy49Z/sotO23Bm6cAB/6
yxMosuIFXa7tqkAHGwy/WIm5PepaL4pvyB\+HVQIDAQABAoIBAQCgKE2yPewBWoMs
tpDi/5xsMXPTu7BuXSfxHN\+eJH9xb15qthL9PufxtVzNjDxS6\+dhF9xlj1fx9Pf5
h3flWStGsfZk0EErajoI9qQw8iokOxd2bSUTyxvVGjATtyjDndXNpqJG3tLV3Zhc
LclIAGHUBM6JrM8fcGlL6msTZW9QmupEU69ih0rHGR50in2e\+Ofp6TWPbwH2PoRn
vj3SOyBAOfZMpsTweYwZm/FhkpSY\+lxXbsPgEasJNm0/F46U7CHlQVSUY248Y\+eB
DzNI7MC5bknqbWg0TDOQtw41RLaGdVUQy9wqC/UlOWb4mteEZXIx3tfNb5W/5V7G
YedSjwgpAoGBAPQiCzsWTdC7cR9YbF4d8Tv9uKNCmZG1Q4dxTnhQJcSFsBTr2f2a
ps3Ej3nW0wQZfVOVaU6dUcyQxgm4x2fi\+TqhAVGdRLSA8iSJTpC99RUn/JdAW/UA
gvGI0iCrkq/BYCjjrKI7ZsHv6urE3I0jnh5\+H969BsZ6XR6IntwmDshrAoGBAOK9
nzlOEZO54VGTRuBF1m0E3GBsVDhrsoFpZSVcgv3h84MK2idMP0XvEBxvOI/I2hGI
kVJ23axxWEmpGzWrBNuJrC0sQKD3g6rdwXSwPsGk0OEXyQVrC3LfLZf3iS\+GDSI7
UYPL01joCXy99fQPCf/dCdpviAlZVO/mlO4Tdd8/AoGAHEQk0L6QW\+6X9m0ifvMw
jyWdTynS5g/6tZ/k2gFNnidsb7\+vCbHyRjjP8\+dvnzXkUN0nyDZm1iydAVsnm1uo
R6WEpZJz9gJIBvru4ctcqQpsMIb/Hqrkflq9GZND9J2LKLDTuCTwjNveczg/4QeS
sy0fO4bfVfOs/HANFKhDZekCgYBnEalyZDGLRIDPEzKxui1Zy07eKgAy0YoIV7\+Z
ty74d6C5HdLC8F8GzEA3nLtKaRPvynO817m2rKNkgJGU2NPRdAinVClgwoLAxiMt
hvxQDDrDR4uigeFna1oPbX\+X8cjAmdRZI\+tDy96cLMHEGp4CCBl1iSN\+lHQOxXNH
seLwAwKBgQDx5QqwZOfmlQ0rx6jf2EoHChbS3JYt1cRJbwzIOakcKh2Jn/agxZJ8
e9o0x8HI89mJd1WejorvSVN1c3IgV5TG10k5PcmOxlv1OhGNFzWgvMXZmvCwwP40
X0BwCgHRB7FvPAMu0hrDmEIJ87edGd1ziRYXpA9Lke/4VQk249pwzA==
-----END RSA PRIVATE KEY-----$})
    end
    its('mode') { should cmp '00400' }
    it { should be_owned_by 'nova' }
    it { should be_grouped_into 'nova' }
  end

  describe file('/var/lib/nova/.ssh/config') do
    its('content') do
      should match(%r{^Host \*
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null$})
    end
    its('mode') { should cmp '00600' }
    it { should be_owned_by 'nova' }
    it { should be_grouped_into 'nova' }
  end

  describe package('libguestfs-tools') do
    it { should be_installed }
  end
end
