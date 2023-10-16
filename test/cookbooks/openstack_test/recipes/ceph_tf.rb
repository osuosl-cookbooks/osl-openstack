include_recipe 'openstack_test::ceph_tf_config'

osl_ceph_test 'openstack' do
  osd_size '4G'
  config node['osl-ceph']['config']
  ipaddress '10.1.2.2'
end

execute 'enable pg_autoscale' do
  command <<~EOC
    ceph mgr module enable pg_autoscaler
    ceph config set global osd_pool_default_pg_autoscale_mode on
    touch /root/pg_autoscale
  EOC
  creates '/root/pg_autoscale'
end

%w(
  volumes
  volumes_ssd
  images
  backups
  vms
).each do |p|
  execute "create pool #{p}" do
    command <<~EOC
      ceph osd pool create #{p} 32
      touch /root/pool-#{p}.done
    EOC
    creates "/root/pool-#{p}.done"
  end
end

secrets = openstack_credential_secrets

osl_ceph_client 'glance' do
  caps(
    mon: 'profile rbd',
    osd: 'profile rbd pool=images'
  )
  key secrets['ceph']['image_token']
  keyname 'client.glance'
  filename '/etc/ceph/ceph.client.glance.keyring'
end

osl_ceph_client 'cinder' do
  caps(
    mon: 'profile rbd',
    osd: 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd pool=images, profile rbd pool=volumes_ssd'
  )
  key secrets['ceph']['block_token']
  keyname 'client.cinder'
  filename '/etc/ceph/ceph.client.cinder.keyring'
end

osl_ceph_client 'cinder-backup' do
  caps(
    mon: 'profile rbd',
    osd: 'profile rbd pool=backups'
  )
  key secrets['ceph']['block_backup_token']
  keyname 'client.cinder-backup'
  filename '/etc/ceph/ceph.client.cinder-backup.keyring'
end
