name             'osl-openstack'
issues_url       'https://github.com/osuosl-cookbooks/osl-openstack/issues'
source_url       'https://github.com/osuosl-cookbooks/osl-openstack'
maintainer       'Oregon State University'
maintainer_email 'systems@osuosl.org'
license          'Apache-2.0'
chef_version     '>= 14.0'
description      'Installs/Configures osl-openstack'
version          '8.1.0'

depends 'apache2'
depends 'base'
depends 'certificate'
depends 'firewall', '>= 2.2.0'
depends 'git'
depends 'ibm-power'
depends 'line'
depends 'memcached'
depends 'openstack-block-storage'
depends 'openstack-common', '~> 19.0'
depends 'openstack-compute'
depends 'openstack-container'
depends 'openstack-dashboard'
depends 'openstack-identity'
depends 'openstack-image'
depends 'openstack-integration-test'
depends 'openstack-network'
depends 'openstack-ops-database'
depends 'openstack-ops-messaging'
depends 'openstack-orchestration'
depends 'openstack-telemetry'
depends 'osl-apache'
depends 'osl-ceph'
depends 'osl-docker'
depends 'osl-nrpe'
depends 'selinux'
depends 'systemd'
depends 'user'
depends 'yum-centos'
depends 'yum-epel'
depends 'yum-kernel-osuosl'
depends 'yum-qemu-ev'

supports 'centos', '~> 7.0'
