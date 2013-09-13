name             'osl-packstack'
maintainer       'Geoffrey Corey'
maintainer_email 'coreyg@osuosl.org'
license          'Apache 2.0'
description      'Installs/Configures a base system for setting up RDO Openstack'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.0.3'


depends "yum"
depends "user"

## TODO: setup ssh keys for root (packstack setup) and ssh keys for nova user

## Also, maybe list the packages here?
