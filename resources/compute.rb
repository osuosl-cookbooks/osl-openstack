resource_name :osl_openstack_compute
provides :osl_openstack_compute
default_action :create
unified_mode true

property :controller, [true, false], default: true
property :compute, [true, false], default: false

action :create do
  osl_repos_openstack 'compute'
  osl_openstack_client 'compute'
  osl_firewall_openstack 'compute'

  s = os_secrets
  c = s['compute']
  p = s['placement']
  auth_endpoint = s['identity']['endpoint']

  if new_resource.controller
    include_recipe 'osl-apache'
    include_recipe 'osl-apache::mod_wsgi'

    osl_openstack_user p['service']['user'] do
      domain_name 'default'
      role_name 'admin'
      project_name 'service'
      password p['service']['pass']
      action [:create, :grant_role]
    end

    osl_openstack_user c['service']['user'] do
      domain_name 'default'
      role_name 'admin'
      project_name 'service'
      password c['service']['pass']
      action [:create, :grant_role]
    end

    osl_openstack_service 'placement' do
      type 'placement'
    end

    osl_openstack_service 'nova' do
      type 'compute'
    end

    %w(
      admin
      internal
      public
    ).each do |int|
      osl_openstack_endpoint "placement-#{int}" do
        endpoint_name 'placement'
        service_name 'placement'
        interface int
        url "http://#{p['endpoint']}:8778"
        region 'RegionOne'
      end

      osl_openstack_endpoint "compute-#{int}" do
        endpoint_name 'compute'
        service_name 'nova'
        interface int
        url "http://#{p['endpoint']}:8774/v2.1"
        region 'RegionOne'
      end
    end

    package %w(
      openstack-nova-api
      openstack-nova-conductor
      openstack-nova-console
      openstack-nova-novncproxy
      openstack-nova-scheduler
      openstack-placement-api
      python2-osc-placement
    )

    file '/etc/httpd/conf.d/00-placement-api.conf' do
      action :delete
      notifies :reload, 'apache2_service[compute]'
      notifies :delete, 'directory[purge distro conf.d]', :immediately
    end

    directory 'purge distro conf.d' do
      path '/etc/httpd/conf.d'
      recursive true
      action :nothing
    end

    template '/etc/placement/placement.conf' do
      cookbook 'osl-openstack'
      owner 'root'
      group 'placement'
      mode '0640'
      sensitive true
      variables(
        auth_endpoint: auth_endpoint,
        database_connection: openstack_database_connection('placement'),
        memcached_endpoint: s['memcached']['endpoint'],
        service_pass: p['service']['pass']
      )
      notifies :run, 'execute[placement: db_sync]', :immediately
      notifies :reload, 'apache2_service[compute]'
    end
  end

  if new_resource.compute
    osl_repos_centos 'default'

    include_recipe 'yum-qemu-ev'

    kernel_module 'tun' do
      action [:install, :load]
    end

    # Disable IPv6 autoconf globally
    cookbook_file '/etc/sysconfig/network' do
      cookbook 'osl-openstack'
    end

    package %w(
      device-mapper
      device-mapper-multipath
      libguestfs-rescue
      libguestfs-tools
      libvirt
      openstack-nova-compute
      python-libguestfs
      sg3_utils
      sysfsutils
    )

    link "/usr/bin/qemu-system-#{node['kernel']['machine']}" do
      to '/usr/libexec/qemu-kvm'
    end

    cookbook_file '/etc/libvirt/libvirtd.conf' do
      cookbook 'osl-openstack'
      notifies :restart, 'service[libvirtd]'
    end

    service 'libvirtd' do
      action [:enable, :start]
    end

    execute 'Deleting default libvirt network' do
      command 'virsh net-destroy default'
      only_if 'virsh net-list | grep -q default'
    end

  end

  delete_lines 'remove dhcpbridge' do
    path '/usr/share/nova/nova-dist.conf'
    pattern '^dhcpbridge.*'
    backup true
  end

  delete_lines 'remove force_dhcp_release' do
    path '/usr/share/nova/nova-dist.conf'
    pattern '^force_dhcp_release.*'
    backup true
  end

  template '/etc/nova/nova.conf' do
    cookbook 'osl-openstack'
    owner 'root'
    group 'nova'
    mode '0640'
    sensitive true
    variables(
      api_database_connection: openstack_database_connection('compute_api'),
      auth_endpoint: auth_endpoint,
      cpu_allocation_ratio: c['cpu_allocation_ratio'],
      database_connection: openstack_database_connection('compute'),
      disk_allocation_ratio: c['disk_allocation_ratio'],
      endpoint: c['endpoint'],
      enabled_filters: c['enabled_filters'],
      image_endpoint: s['image']['endpoint'],
      images_rbd_pool: c['ceph']['images_rbd_pool'],
      memcached_endpoint: s['memcached']['endpoint'],
      metadata_proxy_shared_secret: s['network']['metadata_proxy_shared_secret'],
      neutron_pass: s['network']['service']['pass'],
      placement_pass: s['placement']['service']['pass'],
      rbd_secret_uuid: ceph_fsid,
      rbd_user: c['ceph']['rbd_user'],
      service_pass: c['service']['pass'],
      transport_url: openstack_transport_url
    )
  end

  if new_resource.controller
    execute 'placement: db_sync' do
      command 'placement-manage db sync'
      user 'placement'
      group 'placement'
      action :nothing
    end

    execute 'nova: api_db_sync' do
      command 'nova-manage api_db sync'
      user 'nova'
      group 'nova'
      action :nothing
      subscribes :run, 'template[/etc/nova/nova.conf]', :immediately
    end

    execute 'nova: db_sync' do
      command 'nova-manage db sync'
      user 'nova'
      group 'nova'
      action :nothing
      subscribes :run, 'template[/etc/nova/nova.conf]', :immediately
    end

    execute 'nova: register cell0' do
      command 'nova-manage cell_v2 map_cell0'
      user 'nova'
      group 'nova'
      not_if 'nova-manage cell_v2 list_cells | grep -q cell0'
      action :nothing
      subscribes :run, 'template[/etc/nova/nova.conf]', :immediately
    end

    execute 'nova: create cell1' do
      command 'nova-manage cell_v2 create_cell --name=cell1'
      user 'nova'
      group 'nova'
      not_if 'nova-manage cell_v2 list_cells | grep -q cell1'
      action :nothing
      subscribes :run, 'template[/etc/nova/nova.conf]', :immediately
    end

    execute 'nova: discover hosts' do
      command 'nova-manage cell_v2 discover_hosts'
      user 'nova'
      group 'nova'
      action :nothing
      subscribes :run, 'template[/etc/nova/nova.conf]', :immediately
    end

    apache_app 'placement' do
      cookbook 'osl-openstack'
      template 'wsgi-placement.conf.erb'
      notifies :reload, 'apache2_service[compute]', :immediately
    end

    apache_app 'nova-api' do
      cookbook 'osl-openstack'
      template 'wsgi-nova-api.conf.erb'
      notifies :reload, 'apache2_service[compute]', :immediately
    end

    apache_app 'nova-metadata' do
      cookbook 'osl-openstack'
      template 'wsgi-nova-metadata.conf.erb'
      notifies :reload, 'apache2_service[compute]', :immediately
    end

    apache2_service 'compute' do
      action :nothing
      subscribes :restart, 'delete_lines[remove dhcpbridge]'
      subscribes :restart, 'delete_lines[remove force_dhcp_release]'
      subscribes :reload, 'template[/etc/nova/nova.conf]'
    end

    %w(
      openstack-nova-conductor
      openstack-nova-consoleauth
      openstack-nova-novncproxy
      openstack-nova-scheduler
    ).each do |srv|
      service srv do
        action [:enable, :start]
        subscribes :restart, 'delete_lines[remove dhcpbridge]'
        subscribes :restart, 'delete_lines[remove force_dhcp_release]'
        subscribes :restart, 'template[/etc/nova/nova.conf]'
      end
    end

    certificate_manage 'novnc' do
      cert_path '/etc/nova/pki'
      cert_file 'novnc.pem'
      key_file  'novnc.key'
      chain_file 'novnc-bundle.crt'
      nginx_cert true
      owner 'nova'
      group 'nova'
      notifies :restart, 'service[openstack-nova-novncproxy]'
    end

    template '/etc/sysconfig/openstack-nova-novncproxy' do
      cookbook 'osl-openstack'
      source 'novncproxy.erb'
      variables(
        cert: '/etc/nova/pki/certs/novnc.pem',
        key: '/etc/nova/pki/private/novnc.key'
      )
      notifies :restart, 'service[openstack-nova-novncproxy]'
    end
  end

  service 'openstack-nova-compute' do
    action [:enable, :start]
    subscribes :restart, 'template[/etc/nova/nova.conf]'
  end if new_resource.compute
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
