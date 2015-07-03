require 'chef/provisioning'

# temporary workaround for a bug with chef-provisioning
with_chef_server Chef::Config[:chef_server_url].sub('chefzero', 'http')

controller_os = ENV['CONTROLLER_OS'] || 'chef/centos-6.6'
compute_os = ENV['COMPUTE_OS'] || 'chef/centos-6.6'

machine_batch do
  machine 'controller' do
    machine_options vagrant_options: {
      'vm.box' => controller_os
    }
    add_machine_options vagrant_config: <<-EOF
  config.vm.network "private_network", ip: "192.168.60.10"
EOF
    role 'openstack_vagrant'
    recipe 'osl-openstack::ops_database'
    recipe 'osl-openstack::controller'
    recipe 'openstack-integration-test::setup'
    recipe 'scl'
    file('/etc/chef/encrypted_data_bag_secret',
         File.dirname(__FILE__) +
         '/../default/encrypted_data_bag_secret')
    converge true
  end
  machine 'compute' do
    machine_options vagrant_options: {
      'vm.box' => compute_os
    }
    add_machine_options vagrant_config: <<-EOF
  config.vm.network "private_network", ip: "192.168.60.11"
EOF
    role 'openstack_vagrant'
    recipe 'osl-openstack::compute'
    file('/etc/chef/encrypted_data_bag_secret',
         File.dirname(__FILE__) +
         '/../default/encrypted_data_bag_secret')
    converge true
  end
end
