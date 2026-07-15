resource_name :osl_openstack_messaging
provides :osl_openstack_messaging
default_action :create
unified_mode true

property :user, String, default: 'openstack'
property :pass, String, sensitive: true, required: true
property :cookie, String, sensitive: true
property :primary_node, String

# Per-cloud vhosts/users for the shared tier; each user gets full
# permissions on its own vhost. Entries: { 'vhost', 'user', 'pass' }.
property :vhosts, Array, default: []

# TLS listener (AMQPS 5671): deploy the cert (ssl_search_id picks the
# data-bag item) and point the broker at it. tls_only drops plaintext
# 5672 (only once every client speaks TLS).
property :tls, [true, false], default: false
property :ssl_search_id, String, default: 'wildcard'
property :tls_only, [true, false], default: false

# CMR target group size: a new member auto-joins existing quorum queues
# up to this size.
property :cmr_target_group_size, Integer

# RabbitMQ plugins to enable (management UI + prometheus metrics).
property :plugins, Array, default: %w(rabbitmq_management rabbitmq_prometheus)

action :create do
  # rabbitmq-server comes from the Messaging SIG repo below, not the RDO
  # repos (no EL10 build), so we don't pull osl_repos_openstack here -
  # controllers set those up in their own recipes.
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

  # The EL10 package ships these root-owned, so the rabbitmq user can't
  # start (200/CHDIR, can't write its log) or enable plugins (the 4.x
  # node rewrites /etc/rabbitmq/enabled_plugins itself). No-op on EL8/9.
  %w(/etc/rabbitmq /var/lib/rabbitmq /var/log/rabbitmq).each do |dir|
    directory dir do
      owner 'rabbitmq'
      group 'rabbitmq'
    end
  end

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

  # TLS + CMR live in rabbitmq.conf, written only for the tier (embedded
  # brokers set neither, so the file is absent).
  ssl_dir = '/etc/rabbitmq/ssl'
  ssl_cert = "#{ssl_dir}/certs/cert.pem"
  ssl_key = "#{ssl_dir}/private/key.pem"
  ssl_cacert = "#{ssl_dir}/certs/chain.pem"

  # Cert for the TLS listener; after the package (so the rabbitmq user
  # exists to own it), before rabbitmq.conf references these paths.
  if new_resource.tls
    certificate_manage 'wildcard-rabbitmq' do
      search_id new_resource.ssl_search_id
      cert_path ssl_dir
      cert_file 'cert.pem'
      key_file 'key.pem'
      chain_file 'chain.pem'
      owner 'rabbitmq'
      group 'rabbitmq'
      notifies :restart, 'service[rabbitmq-server]', :immediately
    end
  end

  if new_resource.tls || new_resource.cmr_target_group_size
    template '/etc/rabbitmq/rabbitmq.conf' do
      source 'rabbitmq.conf.erb'
      cookbook 'osl-openstack'
      owner 'rabbitmq'
      group 'rabbitmq'
      mode '0644'
      variables(
        tls: new_resource.tls,
        ssl_cert: ssl_cert,
        ssl_key: ssl_key,
        ssl_cacert: ssl_cacert,
        tls_only: new_resource.tls_only,
        cmr: new_resource.cmr_target_group_size
      )
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

  # Hot-enables on the running broker; no restart needed.
  new_resource.plugins.each do |plugin|
    execute "rabbitmq: enable plugin #{plugin}" do
      command "rabbitmq-plugins enable #{plugin}"
      not_if { openstack_rabbitmq_plugin?(plugin) }
    end
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

  # Per-cloud vhosts/users. After the join so metadata replicates; not_if
  # guards keep secondaries idempotent (they exist there post-join).
  new_resource.vhosts.each do |vh|
    vhost = vh['vhost']
    vh_user = vh['user']
    vh_pass = vh['pass']

    execute "rabbitmq: add vhost #{vhost}" do
      command "rabbitmqctl add_vhost #{vhost}"
      not_if { openstack_rabbitmq_vhost?(vhost) }
    end

    execute "rabbitmq: add user #{vh_user}" do
      command "rabbitmqctl add_user #{vh_user} #{vh_pass}"
      sensitive true
      not_if { openstack_rabbitmq_user?(vh_user) }
    end

    execute "rabbitmq: set permissions #{vh_user} on #{vhost}" do
      command "rabbitmqctl set_permissions -p #{vhost} #{vh_user} \".*\" \".*\" \".*\""
      sensitive true
      not_if { openstack_rabbitmq_permissions?(vh_user, vhost) }
    end
  end
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
