require 'chef/provisioning'

# temporary workaround for a bug with chef-provisioning
with_chef_server Chef::Config[:chef_server_url].sub('chefzero', 'http')

machine_batch do
  machine 'controller' do
    add_machine_options vagrant_config: <<-EOF
  config.vm.network "private_network", ip: "192.168.60.10"
EOF
    role 'openstack_vagrant'
    role 'openstack_ops_database'
    role 'openstack_controller'
    file('/etc/chef/encrypted_data_bag_secret',
         "#{File.dirname(__FILE__)}/test/integration/" \
         'default/encrypted_data_bag_secret')
    converge true
  end
  machine 'compute' do
    add_machine_options vagrant_config: <<-EOF
  config.vm.network "private_network", ip: "192.168.60.11"
EOF
    role 'openstack_vagrant'
    role 'openstack_compute'
    file('/etc/chef/encrypted_data_bag_secret',
         "#{File.dirname(__FILE__)}/test/integration/" \
         'default/encrypted_data_bag_secret')
    converge true
  end
end
