# Puts yoga on the node first, as on every production node, so the client stages zed
osl_repos_openstack 'default' do
  source :osuosl
  version 'yoga'
end

package %w(osuosl-openstack-cli osuosl-openstack-keystone)
