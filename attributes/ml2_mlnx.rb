default['openstack']['network']['plugins'].tap do |p|
  p['mlnx']['path'] = '/etc/neutron/plugins/mlnx/'
  p['mlnx']['filename'] = 'mlnx_conf.ini'
  p['mlnx']['conf'] = {}
  p['sriov_agent']['path'] = '/etc/neutron/plugins/ml2/'
  p['sriov_agent']['filename'] = 'sriov_agent.ini'
  p['sriov_agent']['conf'] = {}
end

default['osl-openstack']['ml2_mlnx'].tap do |conf|
  conf['enabled'] = false
  conf['neo_url'] = 'https://localhost/neo/'
  conf['neo_username'] = 'admin'
end

# Mellanox PCI Vendor/Product ID's
default['osl-openstack']['nova']['pci_passthrough_whitelist']['vendor_id'] = '15b3'
default['osl-openstack']['nova']['pci_passthrough_whitelist']['product_id'] = '1003'
default['osl-openstack']['ml2_conf']['supported_pci_vendor_devs'] = '15b3:1004'
default['osl-openstack']['sriov-agent']['physical_device_mappings'] = []
