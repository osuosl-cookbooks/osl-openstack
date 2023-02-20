source 'https://supermarket.chef.io'

solver :ruby, :required

# OSL Base deps
cookbook 'base', git: 'git@github.com:osuosl-cookbooks/base'
cookbook 'ceph-chef', github: 'osuosl-cookbooks/ceph-chef'
cookbook 'ibm-power', git: 'git@github.com:osuosl-cookbooks/ibm-power.git'
cookbook 'osl-apache', git: 'git@github.com:osuosl-cookbooks/osl-apache'
cookbook 'osl-ceph', git: 'git@github.com:osuosl-cookbooks/osl-ceph'
cookbook 'osl-firewall', git: 'git@github.com:osuosl-cookbooks/osl-firewall'
cookbook 'osl-git', git: 'git@github.com:osuosl-cookbooks/osl-git'
cookbook 'osl-nrpe', git: 'git@github.com:osuosl-cookbooks/osl-nrpe'
cookbook 'osl-php', git: 'git@github.com:osuosl-cookbooks/osl-php'
cookbook 'osl-prometheus', git: 'git@github.com:osuosl-cookbooks/osl-prometheus'
cookbook 'osl-repos', git: 'git@github.com:osuosl-cookbooks/osl-repos'
cookbook 'osl-resources', git: 'git@github.com:osuosl-cookbooks/osl-resources', branch: 'main'
cookbook 'osl-rsync', git: 'git@github.com:osuosl-cookbooks/osl-rsync'
cookbook 'osl-selinux', git: 'git@github.com:osuosl-cookbooks/osl-selinux'
cookbook 'osl-syslog', git: 'git@github.com:osuosl-cookbooks/osl-syslog'
cookbook 'resource_from_hash', git: 'git@github.com:osuosl-cookbooks/resource_from_hash'
cookbook 'yum-kernel-osuosl', git: 'git@github.com:osuosl-cookbooks/yum-kernel-osuosl'
cookbook 'yum-qemu-ev', git: 'git@github.com:osuosl-cookbooks/yum-qemu-ev'

# TODO: temporarily lock to the version we have in osl-docker so we can run chefspec
cookbook 'docker', '~> 7.7.0'

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
