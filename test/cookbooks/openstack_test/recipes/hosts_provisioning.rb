controller = []

unless Chef::Config[:solo]
  search(:node, 'recipes:osl-openstack\:\:controller',
         filter_result: { 'ip' => %w(cloud public_ipv4) }).each do |result|
    controller << result['ip']
  end
end

controller_ip = controller.empty? ? node['cloud']['public_ipv4'] : controller

hostsfile_entry controller_ip do
  hostname 'controller.example.com'
end

node.default['firewall']['range']['osl_managed']['4'] << '192.168.56.0/22'
node.default['firewall']['range']['memcached']['4'] << '192.168.56.0/22'
node.default['firewall']['range']['memcached']['4'] << '140.211.168.0/24'
