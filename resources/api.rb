resource_name :osl_openstack_api
provides :osl_openstack_api
default_action :create
unified_mode true

property :service_name, String, name_property: true
property :type, String, required: true
property :endpoint_name, String, required: true
property :url, String, required: true
property :region, String, required: true

action :create do
  osl_openstack_service new_resource.service_name do
    type new_resource.type
  end

  %w(admin internal public).each do |int|
    osl_openstack_endpoint "#{new_resource.endpoint_name}-#{int}" do
      endpoint_name new_resource.endpoint_name
      service_name new_resource.service_name
      interface int
      url new_resource.url
      region new_resource.region
    end
  end
end
