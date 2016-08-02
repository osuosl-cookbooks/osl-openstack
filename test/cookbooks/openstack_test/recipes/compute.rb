execute 'create-fake-eth1-42' do
  command <<-EOF
    ip link add link eth1 name eth1.42 type vlan id 42
  EOF
  not_if 'ip a show dev eth1.42'
end
