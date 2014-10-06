# osl-openstack default attributes

# Include Fedora attribute fixes that aren't in upstream
case platform
when 'fedora'
  # osl-openstack cookbook attributes
  default['osl-openstack']['openpower']['yum']['repo-key'] = 'http://ftp.osuosl.org/pub/osl/repos/yum/RPM-GPG-KEY-osuosl'
  default['osl-openstack']['openpower']['yum']['uri'] = 'http://ftp.osuosl.org/pub/osl/repos/yum/openpower/f20/ppc64'
  default['osl-openstack']['openpower']['kernel_version'] = '3.16.0-1.fc20.ppc64'
  # openstack-* cookbook attributes
  default['openstack']['compute']['platform']['dbus_service'] = 'dbus'
  default['openstack']['db']['python_packages']['mysql'] = [ 'MySQL-python' ]
  default['openstack']['yum']['uri'] = "http://repos.fedorapeople.org/repos/openstack/openstack-#{node['openstack']['release']}/fedora-20"
  default['openstack']['yum']['repo-key'] = "https://github.com/redhat-openstack/rdo-release/raw/#{node['openstack']['release']}/RPM-GPG-KEY-RDO-#{node['openstack']['release'].capitalize}"
when 'centos'
  default['openstack']['yum']['uri'] = "http://repos.fedorapeople.org/repos/openstack/openstack-#{node['openstack']['release']}/epel-6"
  default['openstack']['yum']['repo-key'] = "https://github.com/redhat-openstack/rdo-release/raw/#{node['openstack']['release']}/RPM-GPG-KEY-RDO-#{node['openstack']['release'].capitalize}"
end

case node['kernel']['machine']
when "ppc64"
  default['modules']['modules'] = [ 'kvm_hv' ]
end
