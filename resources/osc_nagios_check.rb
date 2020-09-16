resource_name :osc_nagios_check
provides :osc_nagios_check
default_action :add

property :parameters, String, default: ''
property :plugin, String, name_property: true

check_openstack = ::File.join(node['nrpe']['plugin_dir'], 'check_openstack')

action :add do
  link "#{node['nrpe']['plugin_dir']}/#{new_resource.plugin}" do
    to "/usr/libexec/openstack-monitoring/checks/oschecks-#{new_resource.plugin}"
  end

  nrpe_check new_resource.name do
    command "/bin/sudo #{check_openstack} #{new_resource.plugin}"
    parameters new_resource.parameters unless new_resource.parameters == ''
  end
end
