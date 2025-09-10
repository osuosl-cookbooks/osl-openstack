alpine_qcow2 = ::File.join(Chef::Config[:file_cache_path], 'alpine.qcow2')
alpine_img = ::File.join(Chef::Config[:file_cache_path], 'alpine.img')

remote_file alpine_qcow2 do
  source 'https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/cloud/generic_alpine-3.22.1-x86_64-bios-cloudinit-r0.qcow2'
  show_progress true
end

execute "qemu-img convert -O raw #{alpine_qcow2} #{alpine_img}" do
  creates alpine_img
end

file '/root/image_upload.sh' do
  mode '0755'
  content <<~EOC
    #!/bin/bash
    set -e
    source /root/openrc
    if ! [ -f /root/image_upload.done ] ; then
      openstack image create \
        --file #{alpine_img} \
        --disk-format raw \
        --container-format bare \
        --property hw_scsi_model=virtio-scsi \
        --property hw_disk_bus=scsi \
        --property hw_qemu_guest_agent=yes \
        --property os_require_quiesce=yes \
        alpine
      touch /root/image_upload.done
    fi
  EOC
end

file '/root/create_flavor.sh' do
  mode '0755'
  content <<~EOF
    #!/bin/bash
    set -e
    source /root/openrc
    if ! [ -f /root/flavor.done ] ; then
      openstack flavor create --ram 512 --vcpus 1 --disk 1 --public default
      touch /root/flavor.done
    fi
  EOF
end
