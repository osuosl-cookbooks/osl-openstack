require 'chef/provisioning'

controller_os = ENV['CONTROLLER_OS'] || 'bento/centos-7.3'
controller_ssh_user = ENV['CONTROLLER_SSH_USER'] || 'centos'
flavor_ref = ENV['FLAVOR'] || 4
provision_role = 'openstack_provisioning'

unless ENV['CHEF_DRIVER'] == 'fog:OpenStack'
  require 'chef/provisioning/vagrant_driver'
  vagrant_box controller_os
  provision_role = 'vagrant_provisioning'
  with_driver "vagrant:#{File.dirname(__FILE__)}/../../../vms"
end

machine 'network' do
  machine_options vagrant_options: {
    'vm.box' => controller_os
  },
                  bootstrap_options: {
                    image_ref: controller_os,
                    flavor_ref: flavor_ref,
                    security_groups: 'no-firewall',
                    key_name: ENV['OS_SSH_KEYPAIR'],
                    floating_ip_pool: ENV['OS_FLOATING_IP_POOL']
                  },
                  ssh_username: controller_ssh_user,
                  convergence_options: {
                    chef_version: '12.18.31'
                  }

  ohai_hints 'openstack' => '{}'
  add_machine_options vagrant_config: <<-EOF
config.vm.network "private_network", ip: "192.168.60.13"
config.vm.provider "virtualbox" do |v|
  v.memory = 4096
  v.cpus = 2
end
EOF
  role provision_role
  role 'separate_network_node' if ENV['SEPARATE_NETWORK_NODE']
  recipe 'osl-openstack::network'
  file('/etc/chef/encrypted_data_bag_secret',
       File.dirname(__FILE__) +
       '/../default/encrypted_data_bag_secret')
  converge true
end
