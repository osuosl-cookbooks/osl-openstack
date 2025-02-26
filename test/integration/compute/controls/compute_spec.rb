local_storage = input('local_storage')
os_release = os.release.to_i

control 'compute' do
  %w(
    libvirt-guests
    openstack-ceilometer-compute
    openstack-nova-compute
  ).each do |s|
    describe service s do
      it { should be_enabled }
      it { should be_running }
    end
  end

  describe user 'nova' do
    its('shell') { should cmp '/bin/sh' }
  end

  describe service 'libvirtd-tcp.socket' do
    it { should be_enabled }
    it { should be_running }
  end

  describe service 'libvirtd' do
    it { should be_enabled }
    it { should be_running }
  end

  describe port 16509 do
    it { should be_listening }
    its('protocols') { should cmp 'tcp' }
    its('addresses') { should cmp '0.0.0.0' }
  end

  describe kernel_module('tun') do
    it { should be_loaded }
  end

  describe kernel_module('kvm_intel') do
    it { should be_loaded }
  end

  describe file '/etc/sysconfig/network' do
    its('content') { should match /^NETWORKING=yes$/ }
    its('content') { should match /^NETWORKING_IPV6=yes$/ }
    its('content') { should match /^IPV6_AUTOCONF=no$/ }
  end

  os_pkgs =
    case os_release
    when 8
      %w(
        device-mapper
        device-mapper-multipath
        libguestfs-rescue
        libguestfs-tools
        libvirt
        openstack-nova-compute
        python3-libguestfs
        sg3_utils
        sysfsutils
      )
    when 9
      %w(
        device-mapper
        device-mapper-multipath
        libguestfs-rescue
        libvirt
        openstack-nova-compute
        python3-libguestfs
        qemu-kvm
        qemu-kvm-device-display-virtio-gpu
        qemu-kvm-device-display-virtio-gpu-pci
        sg3_utils
        sysfsutils
        virt-win-reg
      )
    end

  os_pkgs << 'qemu-kvm-device-display-virtio-vga' if os_release >= 9 && os.arch == 'x86_64'

  os_pkgs.each do |p|
    describe package p do
      it { should be_installed }
    end
  end

  describe file '/usr/bin/qemu-system-x86_64' do
    its('link_path') { should cmp '/usr/libexec/qemu-kvm' }
  end

  %w(/var/run/ceph/guests /var/log/ceph).each do |d|
    describe file(d) do
      its('owner') { should eq 'qemu' }
      its('group') { should include 'libvirt' }
      its('type') { should eq :directory }
    end
  end unless local_storage

  %w(nova cinder qemu).each do |u|
    describe user(u) do
      its('groups') { should include 'ceph' }
    end
  end unless local_storage

  describe ini('/etc/ceph/ceph.conf') do
    its('client.admin socket') { should cmp '/var/run/ceph/guests/$cluster-$type.$id.$pid.$cctid.asok' }
    its('client.rbd concurrent management ops') { should cmp '20' }
    its('client.rbd cache') { should cmp 'true' }
    its('client.rbd cache writethrough until flush') { should cmp 'true' }
    its('client.log file') { should cmp '/var/log/ceph/qemu-guest-$pid.log' }
  end unless local_storage

  %w(cinder cinder-backup).each do |key|
    describe file("/etc/ceph/ceph.client.#{key}.keyring") do
      its('owner') { should eq 'ceph' }
      its('group') { should include 'ceph' }
      its('content') { should match(%r{key = [A-Za-z0-9+/].*==$}) }
    end
  end unless local_storage

  openstack = 'bash -c "source /root/openrc && /usr/bin/openstack'

  describe command("#{openstack} compute service list -f value -c Binary -c Status -c State\"") do
    its('stdout') { should match(/nova-compute enabled up/) }
  end

  describe command('virsh secret-list') do
    its('stdout') do
      should match(/ae3f1d03-bacd-4a90-b869-1a4fabb107f2\s.+ceph client.cinder secret/)
    end
  end unless local_storage

  describe command('virsh secret-get-value ae3f1d03-bacd-4a90-b869-1a4fabb107f2') do
    its('stdout') { should match(/^[A-Za-z0-9+].*==$/) }
  end unless local_storage

  describe file('/tmp/kitchen/cache/secret.xml') do
    it { should_not exist }
  end unless local_storage

  describe file('/etc/sysconfig/libvirt-guests') do
    its('content') { should match(/^ON_BOOT=ignore$/) }
    its('content') { should match(/^ON_SHUTDOWN=shutdown$/) }
    its('content') { should match(/^PARALLEL_SHUTDOWN=25$/) }
    its('content') { should match(/^SHUTDOWN_TIMEOUT=120$/) }
  end

  describe file('/etc/libvirt/libvirtd.conf') do
    its('content') { should match(/^max_clients = 200$/) }
    its('content') { should match(/^max_workers = 200$/) }
    its('content') { should match(/^max_requests = 200$/) }
    its('content') { should match(/^max_client_requests = 50$/) }
  end

  describe command 'virsh net-list' do
    its('stdout') { should_not match /default/ }
  end

  describe file '/etc/modprobe.d/options_kvm_intel.conf' do
    its('content') { should cmp "options kvm_intel nested=1\n" }
  end

  describe file('/var/lib/nova/.ssh/authorized_keys') do
    its('content') { should cmp "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDYOuLkP1F/Sm/dCJAA7kme+ObO4J8x2HrZU40W8QqW4yFqRPKnW5HYLeUpRzIFzWen/LIn6R6lxTfSAnnD8qEEuKbFjH5WRqJYCJeAyaTBTRyU1FHlcTR/EQ/HVZ38TQwCztZgboFb5zmWqYc3/BYBHGA6XeYN5jRcHvZbyaGL+YA1/KPIjpbQfqIPXdHfodoSNX4qQQccYBq2c/rq3Puh7Q9oVph6a2lq0wWsqYyq0vTGHPKFYShVpwDl2Z3c8eB3P7yFRzOR2VNuezJlOgoHz6D/mBObLj1n+yi07bcGbpwAH/rLEyiy4gVdru2qQAcbDL9Yibk96lovim/IH4dV nova-migration\n" }
    its('mode') { should cmp '00600' }
    it { should be_owned_by 'nova' }
    it { should be_grouped_into 'nova' }
  end

  describe file('/var/lib/nova/.ssh/id_rsa') do
    its('content') do
      should cmp('----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA2Dri5D9Rf0pv3QiQAO5JnvjmzuCfMdh62VONFvEKluMhakTy
p1uR2C3lKUcyBc1np/yyJ+kepcU30gJ5w/KhBLimxYx+VkaiWAiXgMmkwU0clNRR
5XE0fxEPx1Wd/E0MAs7WYG6BW+c5lqmHN/wWARxgOl3mDeY0XB72W8mhi/mANfyj
yI6W0H6iD13R36HaEjV+KkEHHGAatnP66tz7oe0PaFaYemtpatMFrKmMqtL0xhzy
hWEoVacA5dmd3PHgdz+8hUczkdlTbnsyZToKB8+g/5gTmy49Z/sotO23Bm6cAB/6
yxMosuIFXa7tqkAHGwy/WIm5PepaL4pvyB+HVQIDAQABAoIBAQCgKE2yPewBWoMs
tpDi/5xsMXPTu7BuXSfxHN+eJH9xb15qthL9PufxtVzNjDxS6+dhF9xlj1fx9Pf5
h3flWStGsfZk0EErajoI9qQw8iokOxd2bSUTyxvVGjATtyjDndXNpqJG3tLV3Zhc
LclIAGHUBM6JrM8fcGlL6msTZW9QmupEU69ih0rHGR50in2e+Ofp6TWPbwH2PoRn
vj3SOyBAOfZMpsTweYwZm/FhkpSY+lxXbsPgEasJNm0/F46U7CHlQVSUY248Y+eB
DzNI7MC5bknqbWg0TDOQtw41RLaGdVUQy9wqC/UlOWb4mteEZXIx3tfNb5W/5V7G
YedSjwgpAoGBAPQiCzsWTdC7cR9YbF4d8Tv9uKNCmZG1Q4dxTnhQJcSFsBTr2f2a
ps3Ej3nW0wQZfVOVaU6dUcyQxgm4x2fi+TqhAVGdRLSA8iSJTpC99RUn/JdAW/UA
gvGI0iCrkq/BYCjjrKI7ZsHv6urE3I0jnh5+H969BsZ6XR6IntwmDshrAoGBAOK9
nzlOEZO54VGTRuBF1m0E3GBsVDhrsoFpZSVcgv3h84MK2idMP0XvEBxvOI/I2hGI
kVJ23axxWEmpGzWrBNuJrC0sQKD3g6rdwXSwPsGk0OEXyQVrC3LfLZf3iS+GDSI7
UYPL01joCXy99fQPCf/dCdpviAlZVO/mlO4Tdd8/AoGAHEQk0L6QW+6X9m0ifvMw
jyWdTynS5g/6tZ/k2gFNnidsb7+vCbHyRjjP8+dvnzXkUN0nyDZm1iydAVsnm1uo
R6WEpZJz9gJIBvru4ctcqQpsMIb/Hqrkflq9GZND9J2LKLDTuCTwjNveczg/4QeS
sy0fO4bfVfOs/HANFKhDZekCgYBnEalyZDGLRIDPEzKxui1Zy07eKgAy0YoIV7+Z
ty74d6C5HdLC8F8GzEA3nLtKaRPvynO817m2rKNkgJGU2NPRdAinVClgwoLAxiMt
hvxQDDrDR4uigeFna1oPbX+X8cjAmdRZI+tDy96cLMHEGp4CCBl1iSN+lHQOxXNH
seLwAwKBgQDx5QqwZOfmlQ0rx6jf2EoHChbS3JYt1cRJbwzIOakcKh2Jn/agxZJ8
e9o0x8HI89mJd1WejorvSVN1c3IgV5TG10k5PcmOxlv1OhGNFzWgvMXZmvCwwP40
X0BwCgHRB7FvPAMu0hrDmEIJ87edGd1ziRYXpA9Lke/4VQk249pwzA==
-----END RSA PRIVATE KEY-----')
    end
    its('mode') { should cmp '00600' }
    it { should be_owned_by 'nova' }
    it { should be_grouped_into 'nova' }
  end

  describe file('/var/lib/nova/.ssh/config') do
    its('content') do
      should cmp("Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null\n")
    end
    its('mode') { should cmp '00600' }
    it { should be_owned_by 'nova' }
    it { should be_grouped_into 'nova' }
  end

  describe file '/etc/logrotate.d/var_log_ceph' do
    its('content') do
      should cmp <<~EOF
        # This file was generated by Chef.
        # Do not modify this file by hand!

        "/var/log/ceph" {
          daily
          maxage 30
          rotate 0
          copytruncate
          missingok
          notifempty
        }
      EOF
    end
  end
end
