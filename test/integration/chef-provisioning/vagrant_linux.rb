require 'chef/provisioning/vagrant_driver'

controller_os = ENV['CONTROLLER_OS'] || 'chef/centos-6.6'
compute_os = ENV['COMPUTE_OS'] || 'chef/centos-6.6'

vagrant_box controller_os
vagrant_box compute_os
with_driver "vagrant:#{File.dirname(__FILE__)}/../../../vms"
