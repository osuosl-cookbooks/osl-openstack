set -x
neutron net-create public --shared --provider:physical_network public \
  --provider:network_type flat
neutron subnet-create public 140.211.168.0/24 --name public \
  --allocation-pool start=140.211.168.45,end=140.211.168.48 \
    --dns-nameserver 140.211.166.130 --dns-nameserver 140.211.166.131 \
    --gateway 140.211.168.1
#neutron net-create backend --shared --provider:physical_network backend \
#  --provider:network_type flat
#neutron subnet-create backend 10.1.100.0/24 --name backend \
#  --allocation-pool start=10.1.100.51,end=10.1.100.100 \
#    --dns-nameserver 140.211.166.130 --gateway 10.1.100.1
neutron net-create private
neutron subnet-create private 192.168.30.0/24 --name private \
  --dns-nameserver 8.8.8.8 --gateway 192.168.30.1
neutron net-update public --router:external
neutron router-create router
neutron router-interface-add router private
neutron router-gateway-set router public
iptables -A INPUT -p tcp --dport 53 ! -s 140.211.168.30/24 -j DROP
iptables -A INPUT -p udp --dport 53 ! -s 140.211.168.30/24 -j DROP
iptables -A INPUT -p udp --dport 67 ! -s 140.211.168.30/24 -j DROP
