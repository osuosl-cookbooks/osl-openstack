name             'osl-openstack'
issues_url       'https://github.com/osuosl-cookbooks/osl-openstack/issues'
source_url       'https://github.com/osuosl-cookbooks/osl-openstack'
maintainer       'Oregon State University'
maintainer_email 'systems@osuosl.org'
license          'Apache-2.0'
chef_version     '>= 16.0'
description      'Installs/Configures osl-openstack'
version          '17.0.1'

depends 'base'
depends 'certificate'
depends 'line'
depends 'logrotate'
depends 'memcached'
depends 'osl-apache'
depends 'osl-ceph'
depends 'osl-firewall'
depends 'osl-memcached'
depends 'osl-mysql'
depends 'osl-nrpe'
depends 'osl-prometheus'
depends 'osl-repos'
depends 'osl-resources'
depends 'yum-kernel-osuosl'

supports 'almalinux', '~> 8.0'
supports 'almalinux', '~> 9.0'

gem 'fog-openstack', '~> 1.1'
