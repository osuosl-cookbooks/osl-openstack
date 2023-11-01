resource_name :osl_openstack_network
provides :osl_openstack_network
default_action :create
unified_mode true

property :controller, [true, false], default: true
property :compute, [true, false], default: false

action :create do
  osl_repos_openstack 'network'
  osl_openstack_client 'network'
  osl_firewall_openstack 'network'

  s = os_secrets
  n = s['network']
  auth_endpoint = s['identity']['endpoint']

  osl_openstack_user n['service']['user'] do
    domain_name 'default'
    role_name 'admin'
    project_name 'service'
    password n['service']['pass']
    action [:create, :grant_role]
  end

  osl_openstack_service 'neutron' do
    type 'network'
  end

  %w(
    admin
    internal
    public
  ).each do |int|
    osl_openstack_endpoint "network-#{int}" do
      endpoint_name 'network'
      service_name 'neutron'
      interface int
      url "http://#{n['endpoint']}:9696"
      region 'RegionOne'
    end
  end

  package %w(
    ebtables
    openstack-neutron
    openstack-neutron-linuxbridge
    openstack-neutron-metering-agent
    openstack-neutron-ml2
  ) if new_resource.controller

  package %w(
    ebtables
    ipset
    openstack-neutron-linuxbridge
  ) if new_resource.compute

  osl_systemd_unit_drop_in 'part_of_iptables' do
    extend Iptables::Cookbook::Helpers
    content({
      'Unit' => {
        'PartOf' => "#{get_service_name(:ipv4)}.service",
      },
    })
    unit_name 'neutron-linuxbridge-agent.service'
  end

  cookbook_file '/etc/neutron/plugins/ml2/ml2_conf.ini' do
    cookbook 'osl-openstack'
    owner 'root'
    group 'neutron'
    mode '0640'
    notifies :restart, 'service[neutron-server]'
  end if new_resource.controller

  link '/etc/neutron/plugin.ini' do
    to '/etc/neutron/plugins/ml2/ml2_conf.ini'
  end if new_resource.controller

  template '/etc/neutron/neutron.conf' do
    cookbook 'osl-openstack'
    owner 'root'
    group 'neutron'
    mode '0640'
    sensitive true
    variables(
      auth_endpoint: auth_endpoint,
      compute_pass: s['compute']['service']['pass'],
      controller: new_resource.controller,
      database_connection: openstack_database_connection('image'),
      memcached_endpoint: s['memcached']['endpoint'],
      service_pass: n['service']['pass'],
      transport_url: openstack_transport_url
    )
    notifies :run, 'execute[neutron: db_sync]', :immediately if new_resource.controller
    notifies :restart, 'service[neutron-server]' if new_resource.controller
  end

  execute 'neutron: db_sync' do
    command <<~EOC
      neutron-db-manage \
      --config-file /etc/neutron/neutron.conf \
      --config-file /etc/neutron/plugins/ml2/ml2_conf.ini \
      upgrade head
    EOC
    user 'neutron'
    group 'neutron'
    action :nothing
  end

  template '/etc/neutron/metadata_agent.ini' do
    cookbook 'osl-openstack'
    owner 'root'
    group 'neutron'
    mode '0640'
    sensitive true
    variables(
      memcached_endpoint: s['memcached']['endpoint'],
      metadata_proxy_shared_secret: n['metadata_proxy_shared_secret'],
      nova_metadata_host: n['nova_metadata_host']
    )
    notifies :restart, 'service[neutron-metadata-agent]'
  end if new_resource.controller

  template '/etc/neutron/plugins/ml2/linuxbridge_agent.ini' do
    cookbook 'osl-openstack'
    owner 'root'
    group 'neutron'
    mode '0640'
    variables(
      local_ip: openstack_vxlan_ip(new_resource.controller),
      physical_interface_mappings: openstack_physical_interface_mappings(new_resource.controller)
    )
    notifies :restart, 'service[neutron-linuxbridge-agent]'
  end

  cookbook_file '/etc/neutron/dhcp_agent.ini' do
    cookbook 'osl-openstack'
    owner 'root'
    group 'neutron'
    notifies :restart, 'service[neutron-dhcp-agent]'
  end if new_resource.controller

  cookbook_file '/etc/neutron/l3_agent.ini' do
    cookbook 'osl-openstack'
    owner 'root'
    group 'neutron'
    notifies :restart, 'service[neutron-l3-agent]'
  end if new_resource.controller

  cookbook_file '/etc/neutron/metering_agent.ini' do
    cookbook 'osl-openstack'
    owner 'root'
    group 'neutron'
    notifies :restart, 'service[neutron-metering-agent]'
  end if new_resource.controller

  %w(
    neutron-dhcp-agent
    neutron-l3-agent
    neutron-metadata-agent
    neutron-metering-agent
    neutron-server
  ).each do |srv|
    service srv do
      subscribes :restart, 'template[/etc/neutron/neutron.conf]'
      action [:enable, :start]
    end
  end if new_resource.controller

  service 'neutron-linuxbridge-agent' do
    subscribes :restart, 'template[/etc/neutron/neutron.conf]'
    action [:enable, :start]
  end

  openstack_physical_interface_mappings(new_resource.controller).each do |network|
    next if network['subnet'].nil? || network['uuid'].nil?
    ip_cmd = "ip netns exec qdhcp-#{network['uuid']}"

    bash "block external dns on #{network['name']}" do
      code <<~EOL
        #{ip_cmd} iptables -A INPUT -p tcp --dport 53 ! -s #{network['subnet']} -j DROP
        #{ip_cmd} iptables -A INPUT -p udp --dport 53 ! -s #{network['subnet']} -j DROP
      EOL
      not_if "#{ip_cmd} iptables -S | egrep \"#{network['subnet']}.*port 53.*DROP\""
    end
  end if new_resource.controller
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
