secrets = openstack_credential_secrets

package 'openstack-cinder'

group 'ceph-block' do
  group_name 'ceph'
  append true
  members %w(cinder)
  action :modify
  notifies :restart, 'service[cinder-volume]', :immediately if node.recipe?('openstack-block-storage::volume')
end

osl_ceph_keyring node['osl-openstack']['block']['rbd_store_user'] do
  key secrets['ceph']['block_token']
  not_if { secrets['ceph']['block_token'].nil? }
  notifies :restart, 'service[cinder-volume]', :immediately if node.recipe?('openstack-block-storage::volume')
end

osl_ceph_keyring node['osl-openstack']['block_backup']['rbd_store_user'] do
  key secrets['ceph']['block_backup_token']
  not_if { secrets['ceph']['block_backup_token'].nil? }
end
