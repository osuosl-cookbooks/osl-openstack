resource_name :osl_openstack_service_user
provides :osl_openstack_service_user
default_action :create
unified_mode true

property :user_name, String, name_property: true
property :password, String, required: true, sensitive: true

action :create do
  osl_openstack_user new_resource.user_name do
    domain_name 'default'
    role_name 'admin'
    project_name 'service'
    password new_resource.password
    action [:create, :grant_role]
  end
end
