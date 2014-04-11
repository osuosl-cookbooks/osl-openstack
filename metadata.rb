name             'osl-openstack'
maintainer       'Geoffrey Corey'
maintainer_email 'coreyg@osuosl.org'
license          'Apache 2.0'
description      'Installs/Configures a base system for setting up RDO Openstack'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.0.7'

recipe "osl-openstack", "Sets up the machine to be added to the foreman-openstack cluster"
recipe "osl-openstack::default", "Sets up base repo information for openstack deployment via Foreman."
recipe "osl-openstack::compute", "Sets up the machine for being a compute node and sets upp ssh for the nova user for resizing/migration"

%w{ centos }.each do |os|
    supports os
end

depends "yum"
