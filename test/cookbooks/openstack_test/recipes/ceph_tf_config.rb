node.default['osl-ceph']['config']['fsid'] = 'ae3f1d03-bacd-4a90-b869-1a4fabb107f2'
node.default['osl-ceph']['config']['mon_initial_members'] = %w(ceph)
node.default['osl-ceph']['config']['mon_host'] = %w(10.1.2.2)
node.default['osl-ceph']['config']['public_network'] = %w(10.1.2.0/23)
node.default['osl-ceph']['config']['cluster_network'] = %w(10.1.2.0/23)
