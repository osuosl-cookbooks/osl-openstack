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

append_if_no_line '/etc/hosts' do
  path '/etc/hosts'
  line "#{controller_ip} controller.example.com"
end

%i(memcached).each do |r|
  edit_resource(:"osl_firewall_#{r}", 'osl-openstack') do
    allowed_ipv4 %w(10.1.100.0/22)
  end
end
