controller = nil
# Find the IP for the controller node
unless Chef::Config[:solo]
  # Search for any public IPs
  search(:node, 'recipes:osl-openstack\:\:controller',
         filter_result: { 'ip' => %w(ipaddress) }).each do |result|
    controller = result['ip']
  end
end

# If controller is empty, this must be the first run on a controller node so use it's local endpoint_ip.
controller_ip = controller.nil? ? node['ipaddress'] : controller

hostsfile_entry controller_ip do
  hostname 'controller.example.com'
end

node.default['firewall']['range']['osl_managed']['4'] << '10.1.100.0/22'
node.default['firewall']['range']['memcached']['4'] << '10.1.100.0/22'
