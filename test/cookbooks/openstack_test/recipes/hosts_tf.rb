append_if_no_line '10.1.2.1' do
  path '/etc/hosts'
  line '10.1.2.1 db.testing.osuosl.org'
  sensitive false
end

append_if_no_line '10.1.2.2' do
  path '/etc/hosts'
  line '10.1.2.2 ceph.testing.osuosl.org'
  sensitive false
end

# The cloud's public name is the haproxy VIP, which terminates TLS; a backend IP here
# would answer the TLS handshake with plain HTTP
append_if_no_line '10.1.2.10' do
  path '/etc/hosts'
  line '10.1.2.10 controller.testing.osuosl.org'
  sensitive false
end

# The bare alias makes `hostname --fqdn`, and so node['fqdn'], the .testing.osuosl.org
# name; compile_time puts these lines in before the ohai reload below
{ '10.1.2.3' => 'controller1', '10.1.2.13' => 'controller2', '10.1.2.4' => 'compute' }.each do |ip, host|
  append_if_no_line ip do
    path '/etc/hosts'
    line "#{ip} #{host}.testing.osuosl.org #{host}"
    sensitive false
    compile_time true
  end
end

# The mq nodes' bare aliases let the cluster's FQDN nodenames (rabbit@mqN.testing.osuosl.org)
# resolve on every node
%w(5 6 7).each_with_index do |octet, i|
  append_if_no_line "10.1.2.#{octet}" do
    path '/etc/hosts'
    line "10.1.2.#{octet} mq#{i + 1}.testing.osuosl.org mq#{i + 1}"
    sensitive false
  end
end

append_if_no_line '10.1.2.101' do
  path '/etc/hosts'
  line '10.1.2.101 db-region2.testing.osuosl.org'
  sensitive false
end

append_if_no_line '10.1.2.103' do
  path '/etc/hosts'
  line '10.1.2.103 controller-region2.testing.osuosl.org'
  sensitive false
end

append_if_no_line '10.1.2.104' do
  path '/etc/hosts'
  line '10.1.2.104 compute-region2.testing.osuosl.org'
  sensitive false
end

# Cloud-init's `127.0.0.1 <host>.novalocal` line wins `hostname --fqdn`; drop it and reload ohai
# at compile time, before the ha block keys keepalived and the upgrade runner by node['fqdn']
if %w(controller1 controller2 compute).include?(node['hostname'])
  ohai 'hostname after .novalocal cleanup' do
    plugin 'hostname'
    action :nothing
    compile_time true
  end

  delete_lines "remove cloud-init .novalocal for #{node['hostname']}" do
    path '/etc/hosts'
    pattern /^[0-9a-f:.]+\s+#{Regexp.escape(node['hostname'])}\.novalocal\b/
    notifies :reload, 'ohai[hostname after .novalocal cleanup]', :immediately
    compile_time true
  end
end

hostname node['hostname'] do
  fqdn "#{node['hostname']}.testing.osuosl.org"
end
