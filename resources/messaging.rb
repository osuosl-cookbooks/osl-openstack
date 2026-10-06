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

# AMQPS on 5671 with the ssl_search_id cert; tls_only drops plaintext 5672,
# so set it only once every client speaks TLS.
property :tls, [true, false], default: false
property :ssl_search_id, String, default: 'wildcard'
property :tls_only, [true, false], default: false

# CMR target group size: a new member auto-joins existing quorum queues
# up to this size.
property :cmr_target_group_size, Integer

# RabbitMQ plugins to enable (management UI + prometheus metrics).
property :plugins, Array, default: %w(rabbitmq_management rabbitmq_prometheus)

action :create do
  # rabbitmq-server comes from the Messaging SIG repo below; RDO has no EL10
  # build, so this resource adds no osl_repos_openstack.
  openstack_rabbitmq_firewall_ports.each do |port|
    osl_firewall_port port do
      osl_only true
    end
  end

  yum_repository 'centos-rabbitmq' do
    description 'CentOS $releasever - RabbitMQ'
    baseurl openstack_rabbitmq_repo
    priority '20'
    gpgkey 'https://www.centos.org/keys/RPM-GPG-KEY-CentOS-SIG-Messaging'
  end

  package 'rabbitmq-server'

  # The EL10 package ships these root-owned, which stops rabbitmq starting
  # or enabling plugins. No-op on EL9.
  %w(/etc/rabbitmq /var/lib/rabbitmq /var/log/rabbitmq).each do |dir|
    directory dir do
      owner 'rabbitmq'
      group 'rabbitmq'
    end
  end

  # Declared first: under unified_mode an :immediately notify to a resource
  # declared later raises.
  service 'rabbitmq-server' do
    action [:enable, :start]
  end

  # Shared Erlang cookie; restart immediately so join_cluster below uses it
  file '/var/lib/rabbitmq/.erlang.cookie' do
    content new_resource.cookie
    sensitive true
    owner 'rabbitmq'
    group 'rabbitmq'
    mode '600'
    notifies :restart, 'service[rabbitmq-server]', :immediately
  end if new_resource.cookie

  # Long node names take the primary's domain; node['fqdn'] can be
  # cloud-init's *.novalocal, which the other members can't resolve.
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

  # rabbitmq_t may only bind amqp_port_t, and EL policy leaves 15692 unreserved
  selinux_port '15692 tcp' do
    port '15692'
    protocol 'tcp'
    secontext 'amqp_port_t'
  end if new_resource.plugins.include?('rabbitmq_prometheus')

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

  # administrator tag = management UI (15672) login for the main user.
  execute "rabbitmq: set user tags #{new_resource.user}" do
    command "rabbitmqctl set_user_tags #{new_resource.user} administrator"
    not_if { openstack_rabbitmq_user_tag?(new_resource.user, 'administrator') }
  end

  # Gate converge_by on the predicate so steady-state runs (and the
  # primary itself) report nothing instead of a phantom join every run.
  if new_resource.primary_node && openstack_rabbitmq_join_needed?(new_resource.primary_node)
    converge_by "join RabbitMQ cluster with primary #{new_resource.primary_node}" do
      openstack_rabbitmq_join_cluster(new_resource.primary_node)
    end
  end

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

    # heat-engine leaks a UUID-named listener/engine_worker queue set per
    # restart (2026-08-13 meltdown); expire any unused for an hour.
    execute "rabbitmq: set policy stale-heat-queues on #{vhost}" do
      command "rabbitmqctl set_policy -p #{vhost} stale-heat-queues " \
              "'^(heat-engine-listener|engine_worker)\\.' '{\"expires\":3600000}' --apply-to queues"
      not_if { openstack_rabbitmq_policy?(vhost, 'stale-heat-queues') }
    end
  end
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
