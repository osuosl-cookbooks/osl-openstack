node.default['osl-ceph']['config']['fsid'] = 'ae3f1d03-bacd-4a90-b869-1a4fabb107f2'
node.default['osl-ceph']['config']['mon_initial_members'] = [node['hostname']]
node.default['osl-ceph']['config']['mon_host'] = [node['ipaddress']]
ceph_network = node['kernel']['machine'] == 'ppc64le' ? %w(140.211.11.0/24) : %w(10.1.100.0/23)
node.default['osl-ceph']['config']['public_network'] = ceph_network
node.default['osl-ceph']['config']['cluster_network'] = ceph_network
