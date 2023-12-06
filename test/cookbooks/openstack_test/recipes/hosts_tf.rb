append_if_no_line '10.1.2.1' do
  path '/etc/hosts'
  line '10.1.2.1 db.example.com'
  sensitive false
end

append_if_no_line '10.1.2.2' do
  path '/etc/hosts'
  line '10.1.2.2 ceph.example.com'
  sensitive false
end

append_if_no_line '10.1.2.3' do
  path '/etc/hosts'
  line '10.1.2.3 controller.example.com'
  sensitive false
end

append_if_no_line '10.1.2.4' do
  path '/etc/hosts'
  line '10.1.2.4 compute.example.com'
  sensitive false
end
