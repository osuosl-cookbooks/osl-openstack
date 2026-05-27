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

# `controller.testing.osuosl.org` is the cloud's public hostname; in HA
# mode it lives on the haproxy VIP (10.1.2.10), not on a specific
# controller. Chef clients hit https://controller.testing.osuosl.org:5000
# expecting haproxy to terminate TLS - if this resolved to a backend IP
# instead, Apache (now plain HTTP behind haproxy) would respond to the
# TLS handshake with HTTP and the client would fail with `record layer
# failure`.
append_if_no_line '10.1.2.10' do
  path '/etc/hosts'
  line '10.1.2.10 controller.testing.osuosl.org'
  sensitive false
end

# Per-host backend addresses for the controllers. The bare hostname is
# included as an alias on the same line so `hostname --fqdn` (which
# resolves the bare hostname back to its canonical /etc/hosts entry)
# returns the .testing.osuosl.org form. Without the bare alias here,
# ohai's fqdn plugin would fall through to DNS and node['fqdn'] would
# end up as just the short hostname, which would not match the keys in
# the multinode.json ha block.
#
# `compile_time true` so these entries land BEFORE the cloud-init
# .novalocal removal + ohai reload below (also compile_time) - the
# ohai reload needs the `.testing.osuosl.org` entry already present
# for `hostname --fqdn` to resolve to the right form.
append_if_no_line '10.1.2.3' do
  path '/etc/hosts'
  line '10.1.2.3 controller1.testing.osuosl.org controller1'
  sensitive false
  compile_time true
end

append_if_no_line '10.1.2.13' do
  path '/etc/hosts'
  line '10.1.2.13 controller2.testing.osuosl.org controller2'
  sensitive false
  compile_time true
end

append_if_no_line '10.1.2.4' do
  path '/etc/hosts'
  line '10.1.2.4 compute.testing.osuosl.org'
  sensitive false
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

# On the controllers, the multinode.json ha block keys
# keepalived's primary/interface/priority/api_listen_ip by
# node['fqdn'] - `controller1.testing.osuosl.org` and
# `controller2.testing.osuosl.org`. Cloud-init lays down both
# `127.0.0.1 <hostname>.novalocal <hostname>` and the IPv6 `::1`
# equivalent in /etc/hosts; those win `hostname --fqdn` lookups on
# file-order, so without removing them node['fqdn'] stays `.novalocal`
# and the ha block lookups all return nil (keepalived then renders
# without an `interface` line and aborts with "Unknown interface!").
#
# `compile_time true` makes the cleanup + ohai reload run *during
# compile*, before osl-openstack::ha later loads and captures
# `k[node['fqdn']]` into its `keepalived_vrrp_instance` resource
# properties. Without compile_time the cleanup would run at converge
# time - too late, because Chef resource properties are evaluated
# eagerly at declaration unless wrapped in `lazy { ... }`.
if %w(controller1 controller2).include?(node['hostname'])
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
