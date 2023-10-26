append_if_no_line node['osl-openstack']['bind_service'] do
  path '/etc/hosts'
  line "#{node['osl-openstack']['bind_service']} controller.example.com"
  sensitive false
end
