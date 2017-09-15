set -x
neutron net-create backend --shared --provider:physical_network backend \
  --provider:network_type flat
neutron subnet-create backend 10.1.100.0/22 --name backend \
  --allocation-pool start=10.1.101.2,end=10.1.101.50 \
    --dns-nameserver 140.211.166.130 --gateway 10.1.100.1
neutron net-create private
neutron subnet-create private 192.168.30.0/24 --name private \
  --dns-nameserver 8.8.8.8 --gateway 192.168.30.1
neutron net-update public --router:external
neutron router-create router
neutron router-interface-add router private
neutron router-gateway-set router public
