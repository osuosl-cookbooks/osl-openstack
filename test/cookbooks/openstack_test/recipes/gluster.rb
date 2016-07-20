include_recipe 'base::glusterfs'
include_recipe 'openstack-image::api'
package 'glusterfs-server'
service 'glusterd' do
  action [:enable, :start]
end
directory '/data/openstack-glance' do
  user node['openstack']['image']['user']
  group node['openstack']['image']['group']
  recursive true
end
execute 'create gluster glance volume' do
  command <<-EOH
    gluster volume create openstack-glance \
      #{node['ipaddress']}:/data/openstack-glance force
    gluster volume start openstack-glance
  EOH
  not_if 'gluster volume status openstack-glance'
end

node.default['osl-openstack']['image']['glance_vol'] =
  "#{node['ipaddress']}:/openstack-glance"
