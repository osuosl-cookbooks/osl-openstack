file '/root/upgrade-test' do
  if node['osl-openstack']['upgrade']
    action :create
  else
    action :delete
  end
end
