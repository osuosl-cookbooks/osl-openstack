name             'osl-openstack'
issues_url       'https://github.com/osuosl-cookbooks/osl-openstack/issues'
source_url       'https://github.com/osuosl-cookbooks/osl-openstack'
maintainer       'Oregon State University'
maintainer_email 'systems@osuosl.org'
license          'Apache 2.0'
description      'Installs/Configures osl-openstack'
long_description 'Installs/Configures osl-openstack'
version          '2.5.8'

%w{ base certificate chef-sugar memcached osl-nrpe kernel-modules
  mysql openstack-block-storage openstack-common openstack-compute
  openstack-dashboard openstack-identity openstack-integration-test
  openstack-image openstack-network openstack-ops-database
  openstack-ops-messaging openstack-orchestration openstack-telemetry selinux
  sudo yum-qemu-ev ibm-power apache2 yum-epel}.each do |cb|
  depends cb
end

depends 'firewall', '>= 2.2.0'
depends 'osl-apache', '>= 2.8.5'
depends 'memcached', '= 3.0.0'
depends 'systemd', '< 3.0.0'
depends 'user'
depends 'yum', '= 3.5.4'
depends 'yum-centos'
depends 'yum-epel'

supports         'centos', '~> 7.0'
