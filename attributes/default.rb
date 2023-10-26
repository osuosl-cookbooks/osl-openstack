# osl-openstack default attributes
default['osl-openstack']['databag_item'] = 'x86'
default['osl-openstack']['ceph']['image'] = false
default['osl-openstack']['ceph']['compute'] = false
default['osl-openstack']['ceph']['volume'] = false
default['osl-openstack']['block']['rbd_store_pool'] = 'volumes'
default['osl-openstack']['block']['rbd_ssd_pool'] = 'volumes_ssd'
default['osl-openstack']['block']['rbd_store_user'] = 'cinder'
default['osl-openstack']['block_backup']['rbd_store_pool'] = 'backups'
default['osl-openstack']['block_backup']['rbd_store_user'] = 'cinder-backup'
default['osl-openstack']['seperate_network_node'] = false
default['osl-openstack']['node_type'] = 'compute'
default['osl-openstack']['external_networks'] = %w(public)
default['osl-openstack']['cluster_name'] = nil
