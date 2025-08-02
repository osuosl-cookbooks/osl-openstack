resource_name :osl_openstack_messaging
provides :osl_openstack_messaging
default_action :create
unified_mode true

property :user, String, default: 'openstack'
property :pass, String, sensitive: true, required: true
property :cookie, String, sensitive: true
property :primary_node, String

action :create do
  osl_repos_openstack 'default'

  osl_firewall_port 'amqp' do
    osl_only true
  end

  osl_firewall_port 'rabbitmq_mgt' do
    osl_only true
  end

  yum_repository 'centos-rabbitmq' do
    description 'CentOS $releasever - RabbitMQ'
    baseurl openstack_rabbitmq_repo
    priority '20'
    gpgkey 'https://www.centos.org/keys/RPM-GPG-KEY-CentOS-SIG-Messaging'
  end

  package 'rabbitmq-server'

  # Declare the service early so the file resources below can notify it
  # via :immediately. With unified_mode resources execute in declaration
  # order, so a notify to a not-yet-declared resource raises an error.
  service 'rabbitmq-server' do
    action [:enable, :start]
  end

  # Synchronize the Erlang cookie across cluster members so they can
  # authenticate to each other. The :immediately restart ensures rabbit
  # is using the new cookie before the join_cluster step below runs.
  file '/var/lib/rabbitmq/.erlang.cookie' do
    content new_resource.cookie
    sensitive true
    owner 'rabbitmq'
    group 'rabbitmq'
    mode '600'
    notifies :restart, 'service[rabbitmq-server]', :immediately
  end if new_resource.cookie

  # Use long (FQDN) Erlang node names so cluster members can resolve
  # each other via the FQDN entries that hosts_tf (or DNS) sets up.
  # Derive the domain from the configured primary_node so the local
  # node lands on the same FQDN suffix as the cluster - using
  # node['fqdn'] here would pick up cloud-init's *.novalocal default
  # which won't match the primary's resolvable name.
  if new_resource.cookie && new_resource.primary_node
    domain = new_resource.primary_node.split('@', 2).last.split('.', 2).last
    local_nodename = "rabbit@#{node['hostname']}.#{domain}"

    file '/etc/rabbitmq/rabbitmq-env.conf' do
      content "USE_LONGNAME=true\nNODENAME=#{local_nodename}\n"
      owner 'rabbitmq'
      group 'rabbitmq'
      mode '0644'
      notifies :restart, 'service[rabbitmq-server]', :immediately
    end
  end

  osl_systemd_unit_drop_in 'ulimit' do
    content({
              'Service' => {
                'LimitNOFILE' => 300000,
              },
            })
    unit_name 'rabbitmq-server.service'
    notifies :restart, 'service[rabbitmq-server]'
  end

  execute "rabbitmq: add user #{new_resource.user}" do
    command "rabbitmqctl add_user #{new_resource.user} #{new_resource.pass}"
    sensitive true
    not_if { openstack_rabbitmq_user?(new_resource.user) }
  end

  execute "rabbitmq: set permissions #{new_resource.user}" do
    command "rabbitmqctl set_permissions #{new_resource.user} \".*\" \".*\" \".*\""
    sensitive true
    not_if { openstack_rabbitmq_permissions?(new_resource.user) }
  end

  converge_by "join RabbitMQ cluster with primary #{new_resource.primary_node}" do
    openstack_rabbitmq_join_cluster(new_resource.primary_node)
  end if new_resource.primary_node
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
