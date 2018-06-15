secrets = openstack_credential_secrets

package 'openstack-cinder'

group 'ceph-block' do
  group_name 'ceph'
  append true
  members %w(cinder)
  action :modify
  notifies :restart, 'service[cinder-volume]', :immediately if node.recipe?('openstack-block-storage::volume')
end

template "/etc/ceph/ceph.client.#{node['osl-openstack']['block']['rbd_store_user']}.keyring" do
  source 'ceph.client.keyring.erb'
  owner node['ceph']['owner']
  group node['ceph']['group']
  sensitive true
  not_if { secrets['ceph']['block_token'].nil? }
  variables(
    ceph_user: node['osl-openstack']['block']['rbd_store_user'],
    ceph_token: secrets['ceph']['block_token']
  )
  notifies :restart, 'service[cinder-volume]', :immediately if node.recipe?('openstack-block-storage::volume')
end

template "/etc/ceph/ceph.client.#{node['osl-openstack']['block_backup']['rbd_store_user']}.keyring" do
  source 'ceph.client.keyring.erb'
  owner node['ceph']['owner']
  group node['ceph']['group']
  sensitive true
  not_if { secrets['ceph']['block_backup_token'].nil? }
  variables(
    ceph_user: node['osl-openstack']['block_backup']['rbd_store_user'],
    ceph_token: secrets['ceph']['block_backup_token']
  )
end
