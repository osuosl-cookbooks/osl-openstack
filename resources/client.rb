resource_name :osl_openstack_client
provides :osl_openstack_client
default_action :create
unified_mode true

property :firewall, [true, false], default: false
property :openrc, [true, false], default: false

action :create do
  osl_repos_openstack 'default' do
    source :osuosl
  end

  package openstack_client_pkg

  osl_openstack_openrc new_resource.name if new_resource.openrc
  osl_firewall_openstack new_resource.name if new_resource.firewall
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
