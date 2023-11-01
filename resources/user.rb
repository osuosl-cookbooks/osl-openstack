resource_name :osl_openstack_user
provides :osl_openstack_user
default_action :create
unified_mode true

property :user_name, String, name_property: true
property :email, String
property :password, String, required: true, sensitive: true
property :role_name, String, required: [:grant_role]
property :project_name, String, required: [:grant_role]
property :domain_name, String

action :create do
  domain = os_domain(new_resource)
  project = os_project(new_resource)
  unless os_user(new_resource)
    if domain
      converge_by("creating user #{new_resource.user_name} in domain #{domain.name}") do
        os_conn.users.create(
          name: new_resource.user_name,
          domain_id: domain.id,
          email: new_resource.email,
          default_project_id: project ? project.id : nil,
          password: new_resource.password
        )
      end
    else
      converge_by("creating user #{new_resource.user_name}") do
        os_conn.users.create(
          name: new_resource.user_name,
          email: new_resource.email,
          default_project_id: project ? project.id : nil,
          password: new_resource.password
        )
      end
    end
  end
end

action :grant_role do
  unless os_user_grant_role(new_resource)
    project = os_project(new_resource)
    role = os_role(new_resource)
    user = os_user(new_resource)
    converge_by("granting role #{new_resource.role_name} to user #{new_resource.user_name} in project #{new_resource.project_name}") do
      project.grant_role_to_user role.id, user.id
    end
  end
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
