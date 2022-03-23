append_if_no_line '/etc/hosts' do
  path '/etc/hosts'
  line "#{node['osl-openstack']['bind_service']} controller.example.com"
end
