file '/root/upgrade-test' do
  if node['osl-openstack']['upgrade']
    action :touch
  else
    action :delete
  end
end
