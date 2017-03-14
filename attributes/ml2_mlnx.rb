node.default['openstack']['network']['plugins'].tap do |p|
  p['mlnx']['path'] = '/etc/neutron/plugins/mlnx/'
  p['mlnx']['filename'] = 'mlnx_conf.ini'
  p['mlnx']['conf'] = {}
  p['eswitchd']['path'] = '/etc/neutron/plugins/ml2/'
  p['eswitchd']['filename'] = 'eswitchd.conf'
  p['eswitchd']['conf'] = {}
end

default['osl-openstack']['ml2_mlnx'].tap do |conf|
  conf['enabled'] = false
  conf['neo_url'] = 'https://localhost/neo/'
end
