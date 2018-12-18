execute 'systemctl start httpd openstack-nova-api'

file '/root/upgrade-test' do
  action :touch
end
