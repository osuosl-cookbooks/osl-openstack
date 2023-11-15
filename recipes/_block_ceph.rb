s = os_secrets

package 'openstack-cinder'

group 'ceph-block' do
  group_name 'ceph'
  append true
  members %w(cinder)
  action :modify
  notifies :restart, 'service[cinder-volume]', :immediately if node.recipe?('osl-openstack::block_storage')
end

osl_ceph_keyring s['block-storage']['ceph']['rbd_store_user'] do
  key s['block-storage']['ceph']['block_token']
  not_if { s['block-storage']['ceph']['block_token'].nil? }
  notifies :restart, 'service[cinder-volume]', :immediately if node.recipe?('osl-openstack::block_storage')
end

osl_ceph_keyring s['block-storage']['ceph']['block_backup_rbd_store_user'] do
  key s['block-storage']['ceph']['block_backup_token']
  not_if { s['block-storage']['ceph']['block_backup_token'].nil? }
end
