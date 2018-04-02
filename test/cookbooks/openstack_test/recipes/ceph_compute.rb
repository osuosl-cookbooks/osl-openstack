controller_node = search(:node, 'recipes:osl-openstack\:\:controller').first
node.default['ceph']['fsid-secret'] = controller_node['ceph']['fsid-secret']
node.default['ceph']['config']['global']['mon host'] = "#{controller_node['ipaddress']}:6789"

include_recipe 'osl-ceph'
