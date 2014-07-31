# osl-openstack default attributes

# Include Fedora attribute fixes that aren't in upstream
case platform
when 'fedora'
  default['openstack']['compute']['platform']['dbus_service'] = 'dbus'
  default['openstack']['db']['python_packages']['mysql'] = 'MySQL-python'
end
