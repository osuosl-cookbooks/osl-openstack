cirros_img = ::File.join(Chef::Config[:file_cache_path], 'cirros.img')

remote_file cirros_img do
  source 'http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img'
  show_progress true
  notifies :run, 'execute[Upload cirros image]', :immediately
end

execute 'Upload cirros image' do
  command <<~EOC
    source /root/openrc
    openstack image create \
      --file #{cirros_img} \
      --disk-format raw \
      --container-format bare \
      --property hw_scsi_model=virtio-scsi \
      --property hw_disk_bus=scsi \
      --property hw_qemu_guest_agent=yes \
      --property os_require_quiesce=yes \
      cirros
  EOC
  live_stream true
  action :nothing
end
