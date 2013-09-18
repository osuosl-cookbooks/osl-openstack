
# RDO repo information
default['osl-packstack']['rdo']['release']  = "grizzly"
default['user']['ssh_keygen'] = "false"
default['osl-packstack']['type'] = "other"
default['osl-packstack']['secret_file'] = "/etc/chef/encrypted_data_bag_secret"

case node['osl-packstack']['type']
when "compute"
  default['users'] = ['packstack-root', 'packstack-nova']
else
  default['users'] = ['packstack-root']
end
