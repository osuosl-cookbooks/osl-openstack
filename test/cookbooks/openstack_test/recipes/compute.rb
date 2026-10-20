osl_fakenic 'eth1.42'

# Multi-node's first compute is the one upgrade canary, whatever CPUs the others land on
node.default['osl-openstack']['upgrade_canary'] = true if node['hostname'] == 'compute'
