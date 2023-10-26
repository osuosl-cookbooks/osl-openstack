resource_name :osl_openstack_project
provides :osl_openstack_project
default_action :create
unified_mode true

property :project_name, String, name_property: true
property :domain_name, String

action :create do
  unless os_project(new_resource)
    converge_by("creating project #{new_resource.project_name}") do
      os_conn.projects.create name: new_resource.project_name
    end
  end
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
