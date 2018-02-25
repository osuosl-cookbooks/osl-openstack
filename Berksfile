source 'https://supermarket.chef.io'

solver :ruby, :required

# OSL Base deps
cookbook 'aliases', git: 'git@github.com:osuosl-cookbooks/aliases'
cookbook 'base', git: 'git@github.com:osuosl-cookbooks/base'
cookbook 'firewall', git: 'git@github.com:osuosl-cookbooks/firewall'
cookbook 'munin', git: 'git@github.com:osuosl-cookbooks/munin'
cookbook 'osl-nrpe', git: 'git@github.com:osuosl-cookbooks/osl-nrpe'
cookbook 'osl-apache', git: 'git@github.com:osuosl-cookbooks/osl-apache'
cookbook 'osl-munin', git: 'git@github.com:osuosl-cookbooks/osl-munin'
cookbook 'osl-php', git: 'git@github.com:osuosl-cookbooks/osl-php'
cookbook 'osl-rsync', git: 'git@github.com:osuosl-cookbooks/osl-rsync'
cookbook 'resource_from_hash',
         git: 'git@github.com:osuosl-cookbooks/resource_from_hash'
cookbook 'statsd', github: 'att-cloud/cookbook-statsd'
cookbook 'yum-qemu-ev', git: 'git@github.com:osuosl-cookbooks/yum-qemu-ev.git'
cookbook 'ibm-power', git: 'git@github.com:osuosl-cookbooks/ibm-power.git'
cookbook 'openstackclient', github: 'cloudbau/cookbook-openstackclient'

# WIP patches
# %w(
# ).each do |cb|
#   cookbook "openstack-#{cb}",
#            github: "osuosl-cookbooks/cookbook-openstack-#{cb}",
#            branch: 'stable/newton'
# end

# Openstack deps
%w(
  block-storage
  common
  compute
  dashboard
  identity
  image
  integration-test
  network
  ops-database
  ops-messaging
  orchestration
  telemetry
).each do |cb|
  cookbook "openstack-#{cb}",
           github: "openstack/cookbook-openstack-#{cb}",
           branch: 'stable/newton'
end

cookbook 'openstack_test', path: 'test/cookbooks/openstack_test'

metadata
