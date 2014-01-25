# -*- mode: ruby -*-
# vi: set ft=ruby tabstop=2 :
require 'vagrant-openstack-plugin'
require 'vagrant-omnibus'
require 'vagrant-berkshelf'

box_ver = "20140121"
box_url = "http://vagrant.osuosl.org/centos-6-#{box_ver}.box"

Vagrant.configure("2") do |config|
  config.vm.network   "forwarded_port", guest: 80, host: 8080, auto_correct: true
  config.vm.box       = "centos-6-#{box_ver}"
  config.vm.hostname  = "osl-packstack-berkshelf"
  config.vm.box_url   = "#{box_url}"

  config.vm.provider "openstack" do |os, override|
    # Your openstack ssh private key location
    override.ssh.private_key_path = "#{ENV['OS_SSH_KEY']}"
    override.ssh.host   = "#{ENV['OS_FLOATING_IP']}"
    override.vm.box     = "openstack"
    override.vm.box_url = "http://vagrant.osuosl.org/openstack.box"

    os.username     = "#{ENV['OS_USERNAME']}"
    os.flavor       = /m1.tiny/
    os.image        = "CentOS 6.5"
    os.endpoint     = "http://10.1.0.27:35357/v2.0/tokens"
    os.keypair_name = "#{ENV['OS_SSH_KEYPAIR']}"
    os.ssh_username = "centos"
    os.security_groups = ['default']
    os.tenant       = "OSL"
    os.server_name  = "#{ENV['USER']}-openstack"
    os.floating_ip  = "#{ENV['OS_FLOATING_IP']}"
  end

  # The path to the Berksfile to use with Vagrant Berkshelf
  # config.berkshelf.berksfile_path = "./Berksfile"

  # Enabling the Berkshelf plugin. To enable this globally, add this configuration
  # option to your ~/.vagrant.d/Vagrantfile file
  config.berkshelf.enabled = true

  # An array of symbols representing groups of cookbook described in the Vagrantfile
  # to exclusively install and copy to Vagrant's shelf.
  # config.berkshelf.only = []

  # An array of symbols representing groups of cookbook described in the Vagrantfile
  # to skip installing and copying to Vagrant's shelf.
  # config.berkshelf.except = []

  config.omnibus.chef_version = :latest

  config.vm.provision "chef_solo" do |chef|

    chef.data_bags_path = "#{ENV['HOME']}/git/chef-repo/data_bags"
    chef.encrypted_data_bag_secret_key_path = "#{ENV['HOME']}/.chef/encrypted_data_bag_secret"

    chef.json = {
      :mysql => {
        :server_root_password => 'rootpass',
        :server_debian_password => 'debpass',
        :server_repl_password => 'replpass'
      }
    }

    chef.run_list = [
      "recipe[osl-packstack::default]"
    ]
  end
end
