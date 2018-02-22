# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/MethodLength
def openstack_credential_secrets
  Chef::EncryptedDataBagItem.load(
    node['osl-openstack']['ceph_databag'],
    node['osl-openstack']['ceph_item']
  )
rescue Net::HTTPServerException => e
  databag = "#{node['osl-openstack']['ceph_databag']}:#{node['osl-openstack']['ceph_item']}"
  if e.response.code == '404'
    Chef::Log.warn("Could not find databag '#{databag}'; falling back to default attributes.")
    node['osl-openstack']['credentials']
  else
    Chef::Log.fatal("Unable to load databag '#{databag}'; exiting. Please fix the databag and try again.")
    raise
  end
end
