db_endpoint = input('db_endpoint')

control 'block-storage-controller' do
  describe package 'openstack-cinder' do
    it { should be_installed }
  end

  describe service 'openstack-cinder-scheduler' do
    it { should be_enabled }
    it { should be_running }
  end

  describe port 8776 do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should include '0.0.0.0' }
  end

  describe ini('/etc/cinder/cinder.conf') do
    its('DEFAULT.backup_ceph_chunk_size') { should cmp '134217728' }
    its('DEFAULT.backup_ceph_conf') { should cmp '/etc/ceph/ceph.conf' }
    its('DEFAULT.backup_ceph_pool') { should cmp 'backups' }
    its('DEFAULT.backup_ceph_stripe_count') { should cmp '0' }
    its('DEFAULT.backup_ceph_stripe_unit') { should cmp '0' }
    its('DEFAULT.backup_ceph_user') { should cmp 'cinder-backup' }
    its('DEFAULT.backup_driver') { should cmp 'cinder.backup.drivers.ceph' }
    its('DEFAULT.enabled_backends') { should cmp 'ceph,ceph_ssd' }
    its('DEFAULT.enable_v3_api') { should cmp 'true' }
    its('DEFAULT.glance_api_servers') { should cmp 'http://controller.example.com:9292' }
    its('DEFAULT.glance_api_version') { should_not cmp '' }
    its('DEFAULT.restore_discard_excess_bytes') { should cmp 'true' }
    its('DEFAULT.volume_clear_size') { should cmp '256' }
    its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
    its('ceph.rados_connect_timeout') { should cmp '-1' }
    its('ceph.rbd_ceph_conf') { should cmp '/etc/ceph/ceph.conf' }
    its('ceph.rbd_flatten_volume_from_snapshot') { should cmp 'false' }
    its('ceph.rbd_max_clone_depth') { should cmp '5' }
    its('ceph.rbd_pool') { should cmp 'volumes' }
    its('ceph.rbd_secret_uuid') { should cmp 'ae3f1d03-bacd-4a90-b869-1a4fabb107f2' }
    its('ceph.rbd_store_chunk_size') { should cmp '4' }
    its('ceph.rbd_user') { should cmp 'cinder' }
    its('ceph.volume_backend_name') { should cmp 'ceph' }
    its('ceph.volume_driver') { should cmp 'cinder.volume.drivers.rbd.RBDDriver' }
    its('ceph_ssd.rados_connect_timeout') { should cmp '-1' }
    its('ceph_ssd.rbd_ceph_conf') { should cmp '/etc/ceph/ceph.conf' }
    its('ceph_ssd.rbd_flatten_volume_from_snapshot') { should cmp 'false' }
    its('ceph_ssd.rbd_max_clone_depth') { should cmp '5' }
    its('ceph_ssd.rbd_pool') { should cmp 'volumes_ssd' }
    its('ceph_ssd.rbd_secret_uuid') { should cmp 'ae3f1d03-bacd-4a90-b869-1a4fabb107f2' }
    its('ceph_ssd.rbd_store_chunk_size') { should cmp '4' }
    its('ceph_ssd.rbd_user') { should cmp 'cinder' }
    its('ceph_ssd.volume_backend_name') { should cmp 'ceph_ssd' }
    its('ceph_ssd.volume_driver') { should cmp 'cinder.volume.drivers.rbd.RBDDriver' }
    its('database.connection') { should cmp "mysql+pymysql://cinder_x86:cinder@#{db_endpoint}:3306/cinder_x86" }
    its('keystone_authtoken.auth_url') { should cmp 'https://controller.example.com:5000/v3' }
    its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.password') { should cmp 'cinder' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
    its('keystone_authtoken.www_authenticate_uri') { should cmp 'https://controller.example.com:5000/v3' }
    its('libvirt.rbd_secret_uuid') { should cmp 'ae3f1d03-bacd-4a90-b869-1a4fabb107f2' }
    its('libvirt.rbd_user') { should cmp 'cinder' }
    its('nova.auth_url') { should cmp 'https://controller.example.com:5000/v3' }
    its('nova.password') { should cmp 'nova' }
    its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
  end

  openstack = 'bash -c "source /root/openrc && /usr/bin/openstack'

  describe command("#{openstack} volume service list -f value -c Binary -c Status -c State\"") do
    its('stdout') { should match(/cinder-scheduler enabled up/) }
  end
end
