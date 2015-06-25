require 'chef/provisioning/vagrant_driver'

vagrant_box 'chef/centos-6.6'
with_driver "vagrant:#{File.dirname(__FILE__)}/vms"
with_machine_options vagrant_options: {
  'vm.box' => 'chef/centos-6.6'
}
