describe service('openstack-glance-api') do
  it { should be_enabled }
  it { should be_running }
end

describe port(9292) do
  it { should be_listening }
  its('protocols') { should include 'tcp' }
  its('addresses') { should include '127.0.0.1' }
end

describe ini('/etc/glance/glance-api.conf') do
  its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
  its('keystone_authtoken.service_token_roles_required') { should cmp 'True' }
  its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
  its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
  its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
end

describe command('bash -c "source /root/openrc && /usr/bin/openstack image list"') do
  its('stdout') do
    should match(/\|\s[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\s\|\scirros.*\s\|\sactive/)
  end
end

describe command('bash -c "source /root/openrc && /usr/bin/openstack image show cirros -c properties -f value"') do
  its('stdout') { should match(/direct_url='rbd:/) }
  its('stdout') { should match(/locations=/) }
end

describe command('rbd ls images') do
  its('stdout') { should match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/) }
end

describe user('glance') do
  its('groups') { should include 'ceph' }
end

describe file('/etc/ceph/ceph.client.glance.keyring') do
  its('content') { should match(%r{key = [A-Za-z0-9+/].*==$}) }
  it { should be_owned_by 'ceph' }
  it { should be_grouped_into 'ceph' }
end
