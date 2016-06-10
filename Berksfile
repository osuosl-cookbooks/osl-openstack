source 'https://supermarket.chef.io'

# OSL Base deps
cookbook 'aliases', git: 'git@github.com:osuosl-cookbooks/aliases'
cookbook 'base', git: 'git@github.com:osuosl-cookbooks/base'
cookbook 'firewall', git: 'git@github.com:osuosl-cookbooks/firewall'
cookbook 'modules', git: 'git@github.com:osuosl-cookbooks/modules-cookbook'
cookbook 'munin'
cookbook 'osl-nrpe', git: 'git@github.com:osuosl-cookbooks/osl-nrpe'
cookbook 'omnibus_updater'
cookbook 'osl-apache', git: 'git@github.com:osuosl-cookbooks/osl-apache'
cookbook 'osl-munin', git: 'git@github.com:osuosl-cookbooks/osl-munin'
cookbook 'resource_from_hash',
         git: 'git@github.com:osuosl-cookbooks/resource_from_hash'
cookbook 'statsd', github: 'att-cloud/cookbook-statsd'

# Openstack deps
%w(
    bare-metal
    database
    data-processing
    integration-test
    object-storage
    orchestration
    telemetry
    block-storage
    common
    compute
    dashboard
    identity
    image
    ops-database
    ops-messaging
    network
  ).each do |cb|
  cookbook "openstack-#{cb}",
           github: "openstack/cookbook-openstack-#{cb}",
           branch: 'master'
end

cookbook 'openstack_test', path: 'test/cookbooks/openstack_test'

metadata
