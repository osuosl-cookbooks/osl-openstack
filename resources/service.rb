resource_name :osl_openstack_service
provides :osl_openstack_service
default_action :create
unified_mode true

property :service_name, String, name_property: true
property :type, String, required: true

action :create do
  unless os_service(new_resource)
    converge_by("creating service #{new_resource.service_name}") do
      os_conn.services.create(
        name: new_resource.service_name,
        type: new_resource.type
      )
    end
  end
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
