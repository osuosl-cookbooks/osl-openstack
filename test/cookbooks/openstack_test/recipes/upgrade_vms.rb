# Multi-node: two VMs per compute, one with a volume, that an upgrade must carry through;
# upgrade_vms.sh check confirms they did, and terraform runs remove_compute.sh on a destroy
file '/root/upgrade_vms.sh' do
  mode '0755'
  content <<~'EOF'
    #!/bin/bash
    set -e
    source /root/openrc
    # openstackclient 6.0.1 (zed) adds Host twice for --long -c Host, so format the JSON
    list_vms() {
      openstack server list --all-projects --long -f json | \
        python3 -c 'import json, sys; [print("%-24s %-8s %s" % (s["Name"], s["Status"], s["Host"])) for s in json.load(sys.stdin)]' | sort
    }
    if [ "$1" = check ] ; then
      list_vms
      bad=$(openstack server list --all-projects -f value -c Name -c Status | awk '$1 ~ /^upgrade-vm-/ && $2 != "ACTIVE"')
      bad+=$(openstack volume list --all-projects -f value -c Name -c Status | awk '$1 ~ /^upgrade-vm-/ && $2 != "in-use"')
      [ -z "$bad" ] || { echo "not ACTIVE or not in-use: $bad" ; exit 1 ; }
      exit 0
    fi
    expected=${1:?usage: upgrade_vms.sh <computes> | check}
    /root/image_upload.sh
    /root/create_flavor.sh
    /root/create_network.sh
    for _ in $(seq 60) ; do
      up=$(openstack compute service list --service nova-compute -f value -c State | grep -cx up || true)
      [ "$up" -ge "$expected" ] && break
      sleep 10
    done
    [ "$up" -ge "$expected" ] || { echo "only $up of $expected nova-compute services are up" ; exit 1 ; }
    runuser -u nova -- nova-manage cell_v2 discover_hosts
    for host in $(openstack compute service list --service nova-compute -f value -c Host -c State | awk '$2 == "up" {print $1}') ; do
      for n in 1 2 ; do
        vm=upgrade-vm-$host-$n
        openstack server show $vm >/dev/null 2>&1 || \
          openstack server create --image alpine --flavor default --network public \
            --availability-zone nova:$host --wait $vm
      done
      vol=upgrade-vm-$host-1
      openstack volume show $vol >/dev/null 2>&1 || openstack volume create --size 1 $vol
      while [ "$(openstack volume show $vol -c status -f value)" = creating ] ; do sleep 2 ; done
      if [ "$(openstack volume show $vol -c status -f value)" = available ] ; then
        openstack server add volume $vol $vol
      fi
      until [ "$(openstack volume show $vol -c status -f value)" = in-use ] ; do sleep 2 ; done
    done
    list_vms
  EOF
end

# Nova refuses to delete a service while an instance is on its host
file '/root/remove_compute.sh' do
  mode '0755'
  content <<~'EOF'
    #!/bin/bash
    host=${1:?usage: remove_compute.sh <host>}
    source /root/openrc
    for id in $(openstack server list --all-projects --host "$host" -f value -c ID) ; do
      timeout 300 openstack server delete --wait "$id" || echo "server $id on $host did not delete"
    done
    for vol in $(openstack volume list --all-projects -f value -c Name | grep -E "^upgrade-vm-$host-[0-9]+$") ; do
      openstack volume delete "$vol" || echo "volume $vol did not delete"
    done
    for id in $(openstack compute service list --service nova-compute --host "$host" -f value -c ID) ; do
      openstack compute service delete "$id"
    done
    for id in $(openstack network agent list --host "$host" -f value -c ID) ; do
      openstack network agent delete "$id"
    done
  EOF
end
