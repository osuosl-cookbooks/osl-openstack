resource_name :osl_openstack_client
provides :osl_openstack_client
default_action :create
unified_mode true

action :create do
  osl_repos_openstack 'default'

  package openstack_client_pkg
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
