source 'https://supermarket.chef.io'

solver :ruby, :required

# OSL Base deps
cookbook 'base', git: 'git@github.com:osuosl-cookbooks/base'
cookbook 'ceph-chef', github: 'osuosl-cookbooks/ceph-chef'
cookbook 'firewall', git: 'git@github.com:osuosl-cookbooks/firewall'
cookbook 'ibm-power', git: 'git@github.com:osuosl-cookbooks/ibm-power.git'
cookbook 'munin', git: 'git@github.com:osuosl-cookbooks/munin'
cookbook 'openstackclient', github: 'openstack/cookbook-openstackclient'
cookbook 'osl-apache', git: 'git@github.com:osuosl-cookbooks/osl-apache', branch: 'ramereth/update-upstream-to-apache2-5.x'
cookbook 'osl-ceph', git: 'git@github.com:osuosl-cookbooks/osl-ceph'
cookbook 'osl-munin', git: 'git@github.com:osuosl-cookbooks/osl-munin'
cookbook 'osl-nrpe', git: 'git@github.com:osuosl-cookbooks/osl-nrpe'
cookbook 'osl-php', git: 'git@github.com:osuosl-cookbooks/osl-php'
cookbook 'osl-rsync', git: 'git@github.com:osuosl-cookbooks/osl-rsync'
cookbook 'osl-selinux', git: 'git@github.com:osuosl-cookbooks/osl-selinux'
cookbook 'resource_from_hash', git: 'git@github.com:osuosl-cookbooks/resource_from_hash'
cookbook 'yum-kernel-osuosl', git: 'git@github.com:osuosl-cookbooks/yum-kernel-osuosl.git'
cookbook 'yum-qemu-ev', git: 'git@github.com:osuosl-cookbooks/yum-qemu-ev.git'

# WIP patches
%w(
  telemetry
).each do |cb|
  cookbook "openstack-#{cb}",
           github: "osuosl-cookbooks/cookbook-openstack-#{cb}",
           branch: 'osuosl/rocky'
end

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
).each do |cb|
  cookbook "openstack-#{cb}",
           github: "openstack/cookbook-openstack-#{cb}",
           branch: 'master'
end

cookbook 'openstack_test', path: 'test/cookbooks/openstack_test'

metadata
