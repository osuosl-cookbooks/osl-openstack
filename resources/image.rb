resource_name :osl_openstack_image
provides :osl_openstack_image
default_action :create
unified_mode true

action :create do
  osl_repos_openstack 'image'
  osl_openstack_client 'image'
  osl_firewall_openstack 'image'

  include_recipe 'osl-ceph'

  s = os_secrets
  i = s['image']
  auth_endpoint = s['identity']['endpoint']

  osl_openstack_user i['service']['user'] do
    domain_name 'default'
    role_name 'admin'
    project_name 'service'
    password i['service']['pass']
    action [:create, :grant_role]
  end

  osl_openstack_service 'glance' do
    type 'image'
  end

  %w(
    admin
    internal
    public
  ).each do |int|
    osl_openstack_endpoint "image-#{int}" do
      endpoint_name 'image'
      service_name 'glance'
      interface int
      url "http://#{i['endpoint']}:9292"
      region 'RegionOne'
    end
  end

  package 'openstack-glance'

  template '/etc/glance/glance-registry.conf' do
    owner 'root'
    group 'glance'
    mode '0640'
    sensitive true
    variables(
      auth_endpoint: auth_endpoint,
      database_connection: openstack_database_connection('image'),
      memcached_endpoint: s['memcached']['endpoint'],
      service_pass: i['service']['pass'],
      transport_url: openstack_transport_url
    )
    notifies :restart, 'service[openstack-glance-registry]'
  end

  template '/etc/glance/glance-api.conf' do
    owner 'root'
    group 'glance'
    mode '0640'
    sensitive true
    variables(
      auth_endpoint: auth_endpoint,
      database_connection: openstack_database_connection('image'),
      memcached_endpoint: s['memcached']['endpoint'],
      rbd_store_pool: i['ceph']['rbd_store_pool'],
      rbd_store_user: i['ceph']['rbd_store_user'],
      service_pass: i['service']['pass'],
      transport_url: openstack_transport_url
    )
    notifies :run, 'execute[glance: db_sync]', :immediately
    notifies :restart, 'service[openstack-glance-api]'
  end

  execute 'glance: db_sync' do
    command 'glance-manage db_sync'
    user 'glance'
    group 'glance'
    action :nothing
  end

  group 'ceph-image' do
    group_name 'ceph'
    append true
    members %w(glance)
    action :modify
    notifies :restart, 'service[openstack-glance-api]', :immediately
  end

  osl_ceph_keyring i['ceph']['rbd_store_user'] do
    key i['ceph']['image_token']
    not_if { i['ceph']['image_token'].nil? }
    notifies :restart, 'service[openstack-glance-api]'
  end

  %w(
    openstack-glance-api
    openstack-glance-registry
  ).each do |srv|
    service srv do
      action [:enable, :start]
    end
  end
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
