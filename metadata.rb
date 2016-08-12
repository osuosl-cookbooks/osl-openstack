name             'osl-openstack'
issues_url       'https://github.com/osuosl-cookbooks/osl-openstack/issues'
source_url       'https://github.com/osuosl-cookbooks/osl-openstack'
maintainer       'Oregon State University'
maintainer_email 'systems@osuosl.org'
license          'Apache 2.0'
description      'Installs/Configures osl-openstack'
long_description 'Installs/Configures osl-openstack'
version          '2.1.0'

%w{ base certificate chef-sugar memcached osl-apache osl-nrpe kernel-modules
  mysql openstack-block-storage openstack-common openstack-compute
  openstack-dashboard openstack-identity openstack-integration-test
  openstack-image openstack-network openstack-ops-database
  openstack-ops-messaging openstack-orchestration openstack-telemetry selinux
  yum-qemu-ev}.each do |cb|
  depends cb
end

depends 'firewall', '>= 2.2.0'

supports         'centos', '~> 7.0'
