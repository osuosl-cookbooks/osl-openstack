# osl-openstack default attributes

# Include Fedora attribute fixes that aren't in upstream
case platform
when 'fedora'
  default['openstack']['compute']['platform']['dbus_service'] = 'dbus'
  default['openstack']['db']['python_packages']['mysql'] = [ 'MySQL-python' ]
  default['openstack']['yum']['uri'] = "http://repos.fedorapeople.org/repos/openstack/openstack-#{node['openstack']['release']}/fedora-20"
  default['openstack']['yum']['repo-key'] = "https://github.com/redhat-openstack/rdo-release/raw/master/RPM-GPG-KEY-RDO-#{node['openstack']['release'].capitalize}"
when 'centos'
  default['openstack']['yum']['uri'] = "http://repos.fedorapeople.org/repos/openstack/openstack-#{node['openstack']['release']}/epel-6"
  default['openstack']['yum']['repo-key'] = "https://github.com/redhat-openstack/rdo-release/raw/master/RPM-GPG-KEY-RDO-#{node['openstack']['release'].capitalize}"
end

case node['kernel']['machine']
when "ppc64"
  default['modules']['modules'] = [ 'kvm_hv' ]
end
