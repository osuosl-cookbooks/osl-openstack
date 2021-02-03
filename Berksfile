source 'https://supermarket.chef.io'

solver :ruby, :required

# OSL Base deps
cookbook 'base', git: 'git@github.com:osuosl-cookbooks/base'
cookbook 'ceph-chef', github: 'osuosl-cookbooks/ceph-chef'
cookbook 'firewall', git: 'git@github.com:osuosl-cookbooks/firewall'
cookbook 'ibm-power', git: 'git@github.com:osuosl-cookbooks/ibm-power.git'
cookbook 'munin', git: 'git@github.com:osuosl-cookbooks/munin'
cookbook 'osl-apache', git: 'git@github.com:osuosl-cookbooks/osl-apache'
cookbook 'osl-ceph', git: 'git@github.com:osuosl-cookbooks/osl-ceph'
cookbook 'osl-git', git: 'git@github.com:osuosl-cookbooks/osl-git'
cookbook 'osl-munin', git: 'git@github.com:osuosl-cookbooks/osl-munin'
cookbook 'osl-nrpe', git: 'git@github.com:osuosl-cookbooks/osl-nrpe'
cookbook 'osl-php', git: 'git@github.com:osuosl-cookbooks/osl-php'
cookbook 'osl-prometheus', git: 'git@github.com:osuosl-cookbooks/osl-prometheus'
cookbook 'osl-repos', git: 'git@github.com:osuosl-cookbooks/osl-repos'
cookbook 'osl-rsync', git: 'git@github.com:osuosl-cookbooks/osl-rsync'
cookbook 'osl-selinux', git: 'git@github.com:osuosl-cookbooks/osl-selinux'
cookbook 'resource_from_hash', git: 'git@github.com:osuosl-cookbooks/resource_from_hash'
cookbook 'yum-kernel-osuosl', git: 'git@github.com:osuosl-cookbooks/yum-kernel-osuosl.git'
cookbook 'yum-qemu-ev', git: 'git@github.com:osuosl-cookbooks/yum-qemu-ev.git'

# WIP patches
# %w(
# ).each do |cb|
#   cookbook "openstack-#{cb}",
#            github: "osuosl-cookbooks/cookbook-openstack-#{cb}",
#            branch: 'osuosl/stein'
# end

# Openstack git
# %w(
#   -block-storage
#   client
#   -common
#   -compute
#   -dashboard
#   -identity
#   -image
#   -integration-test
#   -network
#   -ops-database
#   -ops-messaging
#   -orchestration
#   -telemetry
# ).each do |cb|
#   cookbook "openstack-#{cb}",
#            github: "openstack/cookbook-openstack#{cb}",
#            branch: 'stable/stein'
# end

cookbook 'openstack_test', path: 'test/cookbooks/openstack_test'

metadata
