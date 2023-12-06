resource_name :osl_openstack_role
provides :osl_openstack_role
default_action :create
unified_mode true

property :role_name, String, name_property: true

action :create do
  unless os_role(new_resource)
    converge_by("creating role #{new_resource.role_name}") do
      os_conn.roles.create name: new_resource.role_name
    end
  end
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
