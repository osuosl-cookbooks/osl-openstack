require 'chef/provisioning'

compute_os = ENV['COMPUTE_OS'] || 'bento/centos-7.2'
compute_ssh_user = ENV['COMPUTE_SSH_USER'] || 'centos'
flavor_ref = ENV['FLAVOR'] || 3
provision_role = 'openstack_provisioning'

unless ENV['CHEF_DRIVER'] == 'fog:OpenStack'
  require 'chef/provisioning/vagrant_driver'
  vagrant_box compute_os
  provision_role = 'vagrant_provisioning'
  with_driver "vagrant:#{File.dirname(__FILE__)}/../../../vms"
end

machine 'compute' do
  machine_options vagrant_options: {
    'vm.box' => compute_os
  },
                  bootstrap_options: {
                    image_ref: compute_os,
                    flavor_ref: flavor_ref,
                    security_groups: 'no-firewall',
                    key_name: ENV['OS_SSH_KEYPAIR'],
                    floating_ip_pool: ENV['OS_FLOATING_IP_POOL']
                  },
                  ssh_username: compute_ssh_user,
                  convergence_options: {
                    chef_version: '12.10.24'
                  }

  ohai_hints 'openstack' => '{}'
  add_machine_options vagrant_config: <<-EOF
config.vm.network "private_network", ip: "192.168.60.11"
config.vm.provider "virtualbox" do |v|
  v.memory = 1024
end
EOF
  role provision_role
  recipe 'osl-openstack::compute'
  role 'openstack_cinder'
  file('/etc/chef/encrypted_data_bag_secret',
       File.dirname(__FILE__) +
       '/../default/encrypted_data_bag_secret')
  converge true
end
