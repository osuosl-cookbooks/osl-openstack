if node['osl-openstack']['upgrade']
  include_recipe 'osl-openstack::upgrade'

  execute '/root/upgrade.sh' do
    live_stream true
    creates '/root/yoga-upgrade-done'
    only_if { ::File.exist?('/usr/sbin/httpd') }
  end
end
