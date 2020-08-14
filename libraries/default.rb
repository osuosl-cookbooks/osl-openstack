
def openstack_credential_secrets
  data_bag_item(
    node['osl-openstack']['ceph_databag'],
    node['osl-openstack']['ceph_item']
  )
rescue Net::HTTPClientException => e
  databag = "#{node['osl-openstack']['ceph_databag']}:#{node['osl-openstack']['ceph_item']}"
  if e.response.code == '404'
    Chef::Log.warn("Could not find databag '#{databag}'; falling back to default attributes.")
    node['osl-openstack']['credentials']
  else
    Chef::Log.fatal("Unable to load databag '#{databag}'; exiting. Please fix the databag and try again.")
    raise
  end
rescue ChefSpec::Error::DataBagItemNotStubbed
  node['osl-openstack']['credentials']
end
