append_if_no_line '10.1.2.1' do
  path '/etc/hosts'
  line '10.1.2.1 db.testing.osuosl.org'
  sensitive false
end

append_if_no_line '10.1.2.2' do
  path '/etc/hosts'
  line '10.1.2.2 ceph.testing.osuosl.org'
  sensitive false
end

append_if_no_line '10.1.2.3' do
  path '/etc/hosts'
  line '10.1.2.3 controller.testing.osuosl.org'
  sensitive false
end

append_if_no_line '10.1.2.4' do
  path '/etc/hosts'
  line '10.1.2.4 compute.testing.osuosl.org'
  sensitive false
end

append_if_no_line '10.1.2.101' do
  path '/etc/hosts'
  line '10.1.2.101 db-region2.testing.osuosl.org'
  sensitive false
end

append_if_no_line '10.1.2.103' do
  path '/etc/hosts'
  line '10.1.2.103 controller-region2.testing.osuosl.org'
  sensitive false
end

append_if_no_line '10.1.2.104' do
  path '/etc/hosts'
  line '10.1.2.104 compute-region2.testing.osuosl.org'
  sensitive false
end
