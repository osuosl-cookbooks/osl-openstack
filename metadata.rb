name             'osl-packstack'
maintainer       'Geoffrey Corey'
maintainer_email 'coreyg@osuosl.org'
license          'Apache 2.0'
description      'Installs/Configures a base system for setting up RDO Openstack'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.0.6'

recipe "osl-packstack", "Sets up the machine to be added to the packstack cluster"
recipe "osl-packstack::packstack", "Packstack specific configuration and setup, doesn ot setup the compute node by itself"
recipe "osl-packstack::compute", "Sets up the machine for being a compute node, configures libvirt settings, sets upp ssh for the nova user for resizing/migration"

%w{ centos }.each do |os|
    supports os
end

depends "yum"
depends "user"

## TODO: setup ssh keys for root (packstack setup) and ssh keys for nova user

## Also, maybe list the packages here?
