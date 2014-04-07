default['user']['ssh_keygen'] = "false"
default['osl-packstack']['secret_file'] = "/etc/chef/encrypted_data_bag_secret"
#default['packstack_users'] = ['packstack-nova']
#default['users'] = ['osl-root', 'osl-osuadmin']
if Chef::Config[:solo]
  default['users'] = ['packstack-nova']
end
