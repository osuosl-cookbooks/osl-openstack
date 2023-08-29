node.default['osl-ceph']['config']['fsid'] = 'ae3f1d03-bacd-4a90-b869-1a4fabb107f2'
node.default['osl-ceph']['config']['mon_initial_members'] = [node['hostname']]
node.default['osl-ceph']['config']['mon_host'] = [node['ipaddress']]
node.default['osl-ceph']['config']['public_network'] = %w(10.1.100.0/23)
node.default['osl-ceph']['config']['cluster_network'] = %w(10.1.100.0/23)
