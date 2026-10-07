# Boots alpine and, where cinder is deployed, attaches a volume, so nova and
# cinder reach their privsep daemons through rootwrap
file '/root/boot_instance.sh' do
  mode '0755'
  content <<~EOF
    #!/bin/bash
    set -ex
    source /root/openrc
    /root/image_upload.sh
    /root/create_flavor.sh
    /root/create_network.sh
    if ! openstack server show boot-test >/dev/null 2>&1 ; then
      openstack server create --image alpine --flavor default --network public --wait boot-test
    fi
    if openstack catalog list -f value -c Type | grep -qx volumev3 ; then
      openstack volume show boot-test >/dev/null 2>&1 || openstack volume create --size 1 boot-test
      until [ "$(openstack volume show boot-test -c status -f value)" = available ] ; do sleep 2 ; done
      openstack server add volume boot-test boot-test
      until [ "$(openstack volume show boot-test -c status -f value)" = in-use ] ; do sleep 2 ; done
      openstack server remove volume boot-test boot-test
      until [ "$(openstack volume show boot-test -c status -f value)" = available ] ; do sleep 2 ; done
      openstack volume delete boot-test
    fi
    openstack server show boot-test -c status -f value
  EOF
end
