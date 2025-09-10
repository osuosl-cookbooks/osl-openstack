file '/root/create_network.sh' do
  mode '0755'
  content <<~EOF
    #!/bin/bash
    set -e
    source /root/openrc
    if ! [ -f /var/tmp/public_network ] ; then
      openstack network create --share --provider-network-type=flat --provider-physical-network=public \
        --external --default public
      openstack subnet create public --network public --subnet-range=10.10.1.0/24 \
        --allocation-pool=start=10.10.1.2,end=10.10.1.100 --dns-nameserver 140.211.166.130 \
        --dns-nameserver 140.211.166.131 --gateway 10.10.1.1
      openstack network set --external public
      openstack network show -c id -f value public > /var/tmp/public_network
    fi
  EOF
end
