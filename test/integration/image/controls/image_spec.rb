control 'image' do
  describe service('openstack-glance-api') do
    it { should be_enabled }
    it { should be_running }
  end

  describe port(9292) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should include '0.0.0.0' }
  end

  describe ini('/etc/glance/glance-api.conf') do
    its('database.connection') { should cmp 'mysql+pymysql://glance:glance@localhost:3306/x86_glance' }
    its('DEFAULT.transport_url') { should cmp 'rabbit://openstack:openstack@controller.example.com:5672' }
    its('glance_store.rbd_store_pool') { should cmp 'images' }
    its('glance_store.rbd_store_user') { should cmp 'glance' }
    its('keystone_authtoken.auth_url') { should cmp 'https://controller.example.com:5000/v3' }
    its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
    its('keystone_authtoken.password') { should cmp 'glance' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'true' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('keystone_authtoken.www_authenticate_uri') { should cmp 'https://controller.example.com:5000/v3' }
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
end
