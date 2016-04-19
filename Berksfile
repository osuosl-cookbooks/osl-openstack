source 'https://supermarket.chef.io'

# OSL Base deps
cookbook 'aliases', git: 'git@github.com:osuosl-cookbooks/aliases'
cookbook 'base', git: 'git@github.com:osuosl-cookbooks/base'
cookbook 'firewall', git: 'git@github.com:osuosl-cookbooks/firewall'
cookbook 'modules', git: 'git@github.com:osuosl-cookbooks/modules-cookbook'
cookbook 'monitoring', git: 'git@github.com:osuosl-cookbooks/monitoring'
cookbook 'munin'
cookbook 'osl-nagios', git: 'git@github.com:osuosl-cookbooks/osl-nagios'
cookbook 'osl-nrpe', git: 'git@github.com:osuosl-cookbooks/osl-nrpe'
cookbook 'omnibus_updater'
cookbook 'osl-apache', git: 'git@github.com:osuosl-cookbooks/osl-apache'
cookbook 'osl-munin', git: 'git@github.com:osuosl-cookbooks/osl-munin'
cookbook 'scl'
cookbook 'resource_from_hash',
         git: 'git@github.com:osuosl-cookbooks/resource_from_hash'
cookbook 'statsd', github: 'att-cloud/cookbook-statsd'
cookbook 'yum-fedora'

# Openstack deps
# cookbook 'mysql', '~> 4.1'
%w(openstack-bare-metal openstack-block-storage openstack-common
   openstack-object-storage openstack-ops-database openstack-ops-messaging
   openstack-orchestration openstack-telemetry openstack-identity
   openstack-integration-test openstack-image openstack-network
   openstack-compute openstack-dashboard).each do |cb|
  cookbook cb,
           github: "openstack/cookbook-#{cb}",
           branch: 'stable/liberty'
end

cookbook 'openstack_test', path: 'test/cookbooks/openstack_test'

metadata
