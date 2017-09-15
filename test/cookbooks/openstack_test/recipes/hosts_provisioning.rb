controller = []

# Find the IP for the controller node
unless Chef::Config[:solo]
  public_ip = nil
  local_ip = nil
  # Search for any public IPs
  search(:node, 'recipes:osl-openstack\:\:controller',
         filter_result: { 'ip' => %w(cloud public_ipv4) }).each do |result|
    public_ip = result['ip']
  end
  # Search for any local IPs
  search(:node, 'recipes:osl-openstack\:\:controller',
         filter_result: { 'ip' => %w(cloud local_ipv4) }).each do |result|
    local_ip = result['ip']
  end
  # Don't set if we don't find any
  unless (public_ip.nil? && local_ip.nil?) || (public_ip.empty? && local_ip.empty?)
    controller << if public_ip.empty?
                    local_ip
                  else
                    public_ip
                  end
  end
end

# Set the local endpoint IP in case this is the first chef run
endpoint_ip = node['cloud']['public_ipv4'].empty? ? node['cloud']['local_ipv4'] : node['cloud']['public_ipv4']

# If controller is empty, this must be the first run on a controller node so use it's local endpoint_ip.
controller_ip = controller.empty? ? endpoint_ip : controller

hostsfile_entry controller_ip do
  hostname 'controller.example.com'
end

node.default['firewall']['range']['osl_managed']['4'] << '10.1.100.0/24'
node.default['firewall']['range']['memcached']['4'] << '10.1.100.0/24'
