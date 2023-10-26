resource_name :osl_openstack_identity
provides :osl_openstack_identity
default_action :create
unified_mode true

action :create do
  osl_repos_openstack 'identity'
  osl_openstack_client 'identity'
  osl_firewall_openstack 'identity'
  osl_openstack_openrc 'identity'

  node.default['osl-apache']['listen'] = %w(80 443)

  include_recipe 'certificate::wildcard'
  include_recipe 'osl-memcached'
  include_recipe 'osl-apache'
  include_recipe 'osl-apache::mod_wsgi'
  include_recipe 'osl-apache::mod_ssl'

  package 'openstack-keystone'

  s = os_secrets

  endpoint = s['identity']['endpoint']
  admin_pass = s['users']['admin']

  template '/etc/keystone/keystone.conf' do
    owner 'root'
    group 'keystone'
    mode '0640'
    sensitive true
    variables(
      endpoint: endpoint,
      transport_url: openstack_transport_url,
      memcached_endpoint: s['memcached']['endpoint'],
      database_connection: openstack_database_connection('identity')
    )
    notifies :run, 'execute[keystone: db_sync]', :immediately
  end

  execute 'keystone: db_sync' do
    command 'keystone-manage db_sync'
    user 'keystone'
    group 'keystone'
    action :nothing
  end

  execute 'keystone: fernet_setup' do
    command 'keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone'
    creates '/etc/keystone/fernet-keys/0'
  end

  execute 'keystone: credential_setup' do
    command 'keystone-manage credential_setup --keystone-user keystone --keystone-group keystone'
    creates '/etc/keystone/credential-keys/0'
  end

  execute 'keystone: bootstrap' do
    command <<~EOC
      keystone-manage bootstrap --bootstrap-password #{admin_pass} \
        --bootstrap-admin-url https://#{endpoint}:5000/v3/ \
        --bootstrap-internal-url https://#{endpoint}:5000/v3/ \
        --bootstrap-public-url https://#{endpoint}:5000/v3/ \
        --bootstrap-region-id RegionOne && \
      touch /etc/keystone/bootstrapped
    EOC
    sensitive true
    creates '/etc/keystone/bootstrapped'
  end

  apache_app 'keystone' do
    server_name endpoint
    server_aliases s['identity']['aliases'] if s['identity']['aliases']
    cookbook 'osl-openstack'
    template 'wsgi-keystone.conf.erb'
    notifies :reload, 'apache2_service[osuosl]'
  end
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
