source 'https://supermarket.chef.io'

solver :ruby, :required

# OSL Base deps
cookbook 'aliases', git: 'git@github.com:osuosl-cookbooks/aliases'
cookbook 'base', git: 'git@github.com:osuosl-cookbooks/base'
cookbook 'ceph-chef', github: 'osuosl-cookbooks/ceph-chef'
cookbook 'firewall', git: 'git@github.com:osuosl-cookbooks/firewall'
cookbook 'munin', git: 'git@github.com:osuosl-cookbooks/munin'
cookbook 'osl-ceph', git: 'git@github.com:osuosl-cookbooks/osl-ceph'
cookbook 'osl-docker', git: 'git@github.com:osuosl-cookbooks/osl-docker'
cookbook 'osl-nrpe', git: 'git@github.com:osuosl-cookbooks/osl-nrpe'
cookbook 'osl-selinux', git: 'git@github.com:osuosl-cookbooks/osl-selinux'
cookbook 'osl-apache', git: 'git@github.com:osuosl-cookbooks/osl-apache', branch: 'stable/2.x'
cookbook 'osl-munin', git: 'git@github.com:osuosl-cookbooks/osl-munin'
cookbook 'osl-php', git: 'git@github.com:osuosl-cookbooks/osl-php'
cookbook 'osl-rsync', git: 'git@github.com:osuosl-cookbooks/osl-rsync'
cookbook 'resource_from_hash',
         git: 'git@github.com:osuosl-cookbooks/resource_from_hash'
cookbook 'statsd', github: 'att-cloud/cookbook-statsd'
cookbook 'yum-kernel-osuosl', git: 'git@github.com:osuosl-cookbooks/yum-kernel-osuosl.git'
cookbook 'yum-qemu-ev', git: 'git@github.com:osuosl-cookbooks/yum-qemu-ev.git'
cookbook 'ibm-power', git: 'git@github.com:osuosl-cookbooks/ibm-power.git'
cookbook 'openstackclient',
         git: 'git@github.com:osuosl-cookbooks/cookbook-openstackclient',
         branch: 'lock-fog-openstack'

# WIP patches
%w(
  block-storage
  common
  compute
  dashboard
  identity
  image
  network
  ops-database
  ops-messaging
  orchestration
  telemetry
).each do |cb|
  cookbook "openstack-#{cb}",
           github: "osuosl-cookbooks/cookbook-openstack-#{cb}",
           branch: 'stable/newton-chef13'
end

# Openstack deps
%w(
  integration-test
).each do |cb|
  cookbook "openstack-#{cb}",
           github: "openstack/cookbook-openstack-#{cb}",
           branch: 'stable/newton'
end

cookbook 'openstack_test', path: 'test/cookbooks/openstack_test'

metadata
