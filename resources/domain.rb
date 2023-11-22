resource_name :osl_openstack_domain
provides :osl_openstack_domain
default_action :create
unified_mode true

property :domain_name, String, name_property: true

action :create do
  unless os_domain(new_resource)
    converge_by("creating domain #{new_resource.domain_name}") do
      os_conn.domains.create(name: new_resource.domain_name)
    end
  end
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
