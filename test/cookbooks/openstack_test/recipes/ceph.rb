osl_ceph_test 'openstack'

%w(
  volumes
  volumes_ssd
  images
  backups
  vms
).each do |p|
  execute "create pool #{p}" do
    command <<~EOC
      ceph osd pool create #{p} 64
      touch /root/pool-#{p}.done
    EOC
    creates "/root/pool-#{p}.done"
  end
end

secrets = os_secrets

osl_ceph_client 'glance' do
  caps(
    mon: 'profile rbd',
    osd: 'profile rbd pool=images'
  )
  key secrets['image']['ceph']['image_token']
  keyname 'client.glance'
  filename '/etc/ceph/ceph.client.glance.keyring'
end

osl_ceph_client 'cinder' do
  caps(
    mon: 'profile rbd',
    osd: 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd pool=images, profile rbd pool=volumes_ssd'
  )
  key secrets['block-storage']['ceph']['block_token']
  keyname 'client.cinder'
  filename '/etc/ceph/ceph.client.cinder.keyring'
end

osl_ceph_client 'cinder-backup' do
  caps(
    mon: 'profile rbd',
    osd: 'profile rbd pool=backups'
  )
  key secrets['block-storage']['ceph']['block_backup_token']
  keyname 'client.cinder-backup'
  filename '/etc/ceph/ceph.client.cinder-backup.keyring'
end
