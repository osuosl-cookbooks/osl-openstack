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
  its('addresses') { should include '127.0.0.1' }
end

describe ini('/usr/share/cinder/cinder-dist.conf') do
  its('DEFAULT.logdir') { should cmp nil }
  its('DEFAULT.log-dir') { should cmp '/var/log/cinder' }
end

describe ini('/etc/cinder/cinder.conf') do
  its('DEFAULT.volume_clear_size') { should cmp '256' }
  its('DEFAULT.volume_group') { should cmp 'openstack' }
  its('DEFAULT.enable_v3_api') { should cmp 'true' }
  its('DEFAULT.glance_api_version') { should_not cmp '' }
  its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
  its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
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
  its('ceph_ssd.volume_driver') { should cmp 'cinder.volume.drivers.rbd.RBDDriver' }
  its('ceph_ssd.volume_backend_name') { should cmp 'ceph_ssd' }
  its('ceph_ssd.rbd_pool') { should cmp 'volumes_ssd' }
  its('ceph_ssd.rbd_ceph_conf') { should cmp '/etc/ceph/ceph.conf' }
  its('ceph_ssd.rbd_flatten_volume_from_snapshot') { should cmp 'false' }
  its('ceph_ssd.rbd_max_clone_depth') { should cmp '5' }
  its('ceph_ssd.rbd_store_chunk_size') { should cmp '4' }
  its('ceph_ssd.rados_connect_timeout') { should cmp '-1' }
  its('ceph_ssd.rbd_user') { should cmp 'cinder' }
  its('ceph_ssd.rbd_secret_uuid') { should cmp 'ae3f1d03-bacd-4a90-b869-1a4fabb107f2' }
  its('libvirt.rbd_user') { should cmp 'cinder' }
  its('libvirt.rbd_secret_uuid') { should cmp 'ae3f1d03-bacd-4a90-b869-1a4fabb107f2' }
end

describe command('bash -c "source /root/openrc && cinder service-list"') do
  list_output = '\s*\|\s(block-storage-con|controller|allinone).+\s*\|\snova\s\|\senabled\s\|\s*up' \
    '\s*\|\s[0-9]{4}-[0-9]{2}-[0-9]{2}'
  its(:stdout) { should match(/cinder-scheduler#{list_output}/) }
end
