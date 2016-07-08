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
cookbook 'yum-qemu-ev',
  path: '/home/lance/git/osl/chef-repo/osuosl-cookbooks/yum-qemu-ev'

# Openstack deps (cookbooks that don't have stable/mitaka yet)
%w(
  bare-metal
  data-processing
  database
  object-storage
).each do |cb|
  cookbook "openstack-#{cb}",
           github: "openstack/cookbook-openstack-#{cb}",
           branch: 'master'
end

# WIP patches
%w(
  dashboard
  network
).each do |cb|
  cookbook "openstack-#{cb}",
           github: "osuosl-cookbooks/cookbook-openstack-#{cb}",
           branch: 'stable/mitaka'
end

# Openstack deps
%w(
  block-storage
  common
  compute
  identity
  image
  integration-test
  ops-database
  ops-messaging
  orchestration
  telemetry
).each do |cb|
  cookbook "openstack-#{cb}",
           github: "openstack/cookbook-openstack-#{cb}",
           branch: 'stable/mitaka'
end

cookbook 'openstack_test', path: 'test/cookbooks/openstack_test'

metadata
