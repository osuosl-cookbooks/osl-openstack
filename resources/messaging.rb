resource_name :osl_openstack_messaging
provides :osl_openstack_messaging
default_action :create
unified_mode true

property :user, String, default: 'openstack'
property :pass, String, sensitive: true, required: true

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

  osl_systemd_unit_drop_in 'ulimit' do
    content({
      'Service' => {
        'LimitNOFILE' => 300000,
      },
    })
    unit_name 'rabbitmq-server.service'
    notifies :restart, 'service[rabbitmq-server]'
  end

  service 'rabbitmq-server' do
    action [:enable, :start]
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
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end
