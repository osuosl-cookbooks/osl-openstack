# osl-openstack default attributes

default['osl-openstack']['databases'] = {
  'bare-metal' => 'ironic',
  'block-storage' => 'cinder',
  'compute' => 'nova',
  'compute_api' => 'nova_api',
  'dashboard' => 'horizon',
  'database' => 'trove',
  'identity' => 'keystone',
  'image' => 'glance',
  'network' => 'neutron',
  'object-storage' => 'swift',
  'orchestration' => 'heat',
  'telemetry' => 'ceilometer',
}
default['osl-openstack']['data_bags'] = %w(
  db_passwords
  secrets
  service_passwords
  user_passwords
)
default['osl-openstack']['credentials']['ceph'] = {}
default['osl-openstack']['ceph'] = false
default['osl-openstack']['ceph_databag'] = 'ceph'
default['osl-openstack']['ceph_item'] = 'openstack'
default['osl-openstack']['cluster_role'] = 'openstack'
default['osl-openstack']['database_suffix'] = nil
default['osl-openstack']['databag_prefix'] = nil
default['osl-openstack']['compute']['rbd_store_pool'] = 'vms'
default['osl-openstack']['cinder']['iscsi_role'] = nil
default['osl-openstack']['cinder']['iscsi_ips'] = []
default['osl-openstack']['block']['rbd_store_pool'] = 'volumes'
default['osl-openstack']['block']['rbd_ssd_pool'] = 'volumes_ssd'
default['osl-openstack']['block']['rbd_store_user'] = 'cinder'
default['osl-openstack']['block_backup']['rbd_store_pool'] = 'backups'
default['osl-openstack']['block_backup']['rbd_store_user'] = 'cinder-backup'
default['osl-openstack']['image']['glance_vol'] = nil
default['osl-openstack']['image']['rbd_store_pool'] = 'images'
default['osl-openstack']['image']['rbd_store_user'] = 'glance'
default['osl-openstack']['telemetry-metric']['rbd_store_pool'] = 'metrics'
default['osl-openstack']['telemetry-metric']['rbd_store_user'] = 'gnocchi'
default['osl-openstack']['endpoint_hostname'] = nil
default['osl-openstack']['network_hostname'] = nil
default['osl-openstack']['db_hostname'] = nil
default['osl-openstack']['bind_service'] = node['ipaddress']
default['osl-openstack']['seperate_network_node'] = false
default['osl-openstack']['physical_interface_mappings'] = []
default['osl-openstack']['vxlan_interface'] = {
  'controller' => {
    'default' => 'eth0',
  },
  'compute' => {
    'default' => 'eth0',
  },
}
default['osl-openstack']['node_type'] = 'compute'
default['osl-openstack']['nova_ssl_dir'] = '/etc/nova/pki'
default['osl-openstack']['libvirt_guests'] = {
  'on_boot' => 'ignore',
  'on_shutdown' => 'shutdown',
  'parallel_shutdown' => '25',
  'shutdown_timeout' => '120',
}
default['osl-openstack']['novnc'] = {
  'use_ssl' => true,
  'cert_file' => 'novnc.pem',
  'key_file' => 'novnc.key',
}
