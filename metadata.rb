name             'osl-openstack'
issues_url       'https://github.com/osuosl-cookbooks/osl-openstack/issues'
source_url       'https://github.com/osuosl-cookbooks/osl-openstack'
maintainer       'Oregon State University'
maintainer_email 'systems@osuosl.org'
license          'Apache 2.0'
description      'Installs/Configures osl-openstack'
long_description 'Installs/Configures osl-openstack'
version          '3.1.6'

%w{ base certificate chef-sugar git memcached osl-nrpe kernel-modules
  mysql openstack-block-storage openstack-common openstack-compute
  openstack-dashboard openstack-identity openstack-integration-test
  openstack-image openstack-network openstack-ops-database
  openstack-ops-messaging openstack-orchestration openstack-telemetry selinux
  sudo yum-qemu-ev ibm-power apache2 yum-epel}.each do |cb|
  depends cb
end

depends 'build-essential'
depends 'firewall', '>= 2.2.0'
depends 'osl-apache', '>= 2.8.5'
depends 'systemd', '< 3.0.0'
depends 'user'
depends 'yum-centos'

supports         'centos', '~> 7.0'
