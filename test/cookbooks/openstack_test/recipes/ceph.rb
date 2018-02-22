%w(
  volumes
  images
  backups
  vms
).each do |p|
  ceph_chef_pool p do
    pg_num 2
    pgp_num 2
  end
  execute "rbd pool init #{p}"
end

execute 'client.glance' do
  command 'ceph auth get-or-create client.glance mon \'profile rbd\' osd \'profile rbd pool=images\' ' \
          '> /etc/ceph/ceph.client.glance.keyring'
  creates '/etc/ceph/ceph.client.glance.keyring'
end

execute 'client.cinder' do
  command 'ceph auth get-or-create client.cinder mon \'profile rbd\' osd \'profile rbd pool=volumes, ' \
          'profile rbd pool=vms, profile rbd pool=images\' > /etc/ceph/ceph.client.cinder.keyring'
  creates '/etc/ceph/ceph.client.cinder.keyring'
end

execute 'client.cinder-backup' do
  command 'ceph auth get-or-create client.cinder-backup mon \'profile rbd\' osd \'profile rbd pool=backups\' ' \
          '> /etc/ceph/ceph.client.cinder-backup.keyring'
  creates '/etc/ceph/ceph.client.cinder-backup.keyring'
end

ruby_block 'set demo keys' do
  block do
    node.normal['osl-openstack']['credentials']['ceph']['image_token'] = ceph_demo_glance_key
    node.normal['osl-openstack']['credentials']['ceph']['block_token'] = ceph_demo_cinder_key
    node.normal['osl-openstack']['credentials']['ceph']['block_backup_token'] = ceph_demo_cinder_backup_key
  end
end
