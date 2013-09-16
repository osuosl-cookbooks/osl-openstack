
# RDO repo information
default['osl-packstack']['rdo']['release']  = "grizzly"
default['user']['ssh_keygen'] = "false"
default['osl-packstack']['type'] = "other"

case node['osl-packstack']['type']
when "compute"
  default['users'] = ['packstack-root', 'packstack-nova']
else
  default['users'] = ['packstack-root']
end
