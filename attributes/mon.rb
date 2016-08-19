default['osl-openstack']['mon']['check_nova_services'] = {
  'warning' => '5:',
  'critical' => '4:'
}
default['osl-openstack']['mon']['check_nova_hypervisors'] = {
  'warn_memory_percent' => '0:80',
  'critical_memory_percent' => '0:90',
  'warn_vcpus_percent' => '0:80',
  'critical_vcpus_percent' => '0:90'
}
default['osl-openstack']['mon']['check_nova_images'] = {
  'warning' => 1,
  'critical' => 2
}
default['osl-openstack']['mon']['check_neutron_agents'] = {
  'warning' => '5:',
  'critical' => '4:'
}
default['osl-openstack']['mon']['check_cinder_services'] = {
  'warning' => '2:',
  'critical' => '1:'
}
