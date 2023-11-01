resource_name :osl_openstack_endpoint
provides :osl_openstack_endpoint
default_action :create
unified_mode true

property :endpoint_name, String, name_property: true
property :service_name, String, required: true
property :interface, String, required: true
property :url, String, required: true
property :region, String

action :create do
  unless os_endpoint(new_resource)
    converge_by("creating endpoint #{new_resource.endpoint_name}") do
      os_conn.endpoints.create(
        interface: new_resource.interface,
        url: new_resource.url,
        service_id: os_service(new_resource).id,
        name: new_resource.endpoint_name,
        region: new_resource.region
      )
    end
  end
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
