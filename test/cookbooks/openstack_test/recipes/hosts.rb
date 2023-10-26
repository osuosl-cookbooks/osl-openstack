append_if_no_line node['ipaddress'] do
  path '/etc/hosts'
  line "#{node['ipaddress']} controller.example.com"
  sensitive false
end
