default['osl-openstack']['mellanox_neo']['server_hostname'] = node['fqdn']
default['osl-openstack']['mellanox_neo']['packages'] = %w(
  neo-controller
  neo-provider-ac
  neo-provider-common
  neo-provider-discovery
  neo-provider-dm
  neo-provider-ethdisc
  neo-provider-ib
  neo-provider-monitor
  neo-provider-performance
  neo-provider-provisioning
  neo-provider-solution
  neo-provider-virtualization
)
default['osl-openstack']['mellanox_neo']['services'] = %w(
  neo-access-credentials
  neo-controller
  neo-device-manager
  neo-eth-discovery
  neo-ib
  neo-ip-discovery
  neo-monitor
  neo-performance
  neo-provisioning
  neo-solution
  neo-virtualization
)
