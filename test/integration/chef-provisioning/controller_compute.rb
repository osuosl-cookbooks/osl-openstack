require 'chef/provisioning'

# temporary workaround for a bug with chef-provisioning
with_chef_server Chef::Config[:chef_server_url].sub('chefzero', 'http')

controller_os = ENV['CONTROLLER_OS'] || 'chef/centos-7.1'
compute_os = ENV['COMPUTE_OS'] || 'chef/centos-7.1'
controller_ssh_user = ENV['CONTROLLER_SSH_USER'] || 'centos'
compute_ssh_user = ENV['COMPUTE_SSH_USER'] || 'centos'
flavor_ref = ENV['FLAVOR'] || 3

unless ENV['CHEF_DRIVER'] == 'fog:OpenStack'
  require 'chef/provisioning/vagrant_driver'
  vagrant_box controller_os
  vagrant_box compute_os
  with_driver "vagrant:#{File.dirname(__FILE__)}/../../../vms"
end

machine 'controller' do
  machine_options vagrant_options: {
    'vm.box' => controller_os
  },
                  bootstrap_options: {
                    image_ref: controller_os,
                    flavor_ref: flavor_ref,
                    key_name: ENV['OS_SSH_KEYPAIR']
                  },
                  ssh_username: controller_ssh_user,
                  floating_ip_pool: ENV['OS_FLOATING_IP_POOL']

  ohai_hints 'openstack' => '{}'
  add_machine_options vagrant_config: <<-EOF
config.vm.network "private_network", ip: "192.168.60.10"
config.vm.provider "virtualbox" do |v|
  v.memory = 1024
  v.cpus = 2
end
EOF
  role 'openstack_provisioning'
  recipe 'osl-openstack::ops_database'
  recipe 'osl-openstack::controller'
  recipe 'openstack-integration-test::setup'
  file('/etc/chef/encrypted_data_bag_secret',
       File.dirname(__FILE__) +
       '/../default/encrypted_data_bag_secret')
  converge true
end

machine 'compute' do
  machine_options vagrant_options: {
    'vm.box' => compute_os
  },
                  bootstrap_options: {
                    image_ref: compute_os,
                    flavor_ref: flavor_ref,
                    key_name: ENV['OS_SSH_KEYPAIR']
                  },
                  ssh_username: compute_ssh_user,
                  floating_ip_pool: ENV['OS_FLOATING_IP_POOL']

  ohai_hints 'openstack' => '{}'
  add_machine_options vagrant_config: <<-EOF
config.vm.network "private_network", ip: "192.168.60.11"
EOF
  role 'openstack_provisioning'
  recipe 'osl-openstack::compute'
  file('/etc/chef/encrypted_data_bag_secret',
       File.dirname(__FILE__) +
       '/../default/encrypted_data_bag_secret')
  converge true
end
