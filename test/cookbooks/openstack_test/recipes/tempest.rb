package 'openstack-tempest'

s = os_secrets
auth_endpoint = s['identity']['endpoint']

template '/etc/tempest/tempest.conf' do
  variables(
    admin_password: s['users']['admin'],
    auth_endpoint: auth_endpoint
  )
end
