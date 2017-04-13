node.default['openstack']['network']['plugins'].tap do |p|
  p['mlnx']['path'] = '/etc/neutron/plugins/mlnx/'
  p['mlnx']['filename'] = 'mlnx_conf.ini'
  p['mlnx']['conf'] = {}
end

default['osl-openstack']['ml2_mlnx'].tap do |conf|
  conf['enabled'] = false
  conf['neo_url'] = 'https://localhost/neo/'
  conf['neo_username'] = 'admin'
end
