name             'osl-openstack'
maintainer       'Oregon State University'
maintainer_email 'systems@osuosl.org'
license          'Apache 2.0'
description      'Installs/Configures osl-openstack'
long_description 'Installs/Configures osl-openstack'
version          '1.0.16'

%w{ base firewall certificate memcached osl-apache osl-nrpe modules mysql
  openstack-block-storage openstack-common openstack-compute openstack-dashboard
  openstack-identity openstack-integration-test openstack-image
  openstack-network openstack-object-storage openstack-ops-database
  openstack-ops-messaging openstack-orchestration openstack-telemetry selinux
  yum-fedora}.each do |cb|
  depends cb
end
