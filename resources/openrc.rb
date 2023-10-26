resource_name :osl_openstack_openrc
provides :osl_openstack_openrc
default_action :create
unified_mode true

action :create do
  s = os_secrets
  endpoint = s['identity']['endpoint']
  admin_pass = s['users']['admin']

  template '/root/openrc' do
    mode '0750'
    sensitive true
    variables(
      endpoint: endpoint,
      pass: admin_pass
    )
  end
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
