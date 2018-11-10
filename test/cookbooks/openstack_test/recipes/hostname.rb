hostname node['openstack_test']['fqdn']

# execute 'nmcli con modify eth0 ipv4.dhcp-send-hostname "no"' do
#  not_if 'nmcli con show eth0 | grep -q "ipv4.dhcp-send-hostname.*no"'
# end
