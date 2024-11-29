db_endpoint = input('db_endpoint')
controller_endpoint = input('controller_endpoint')
local_storage = input('local_storage')

control 'image' do
  describe service 'openstack-glance-api' do
    it { should be_enabled }
    it { should be_running }
  end

  describe port 9292 do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should include '0.0.0.0' }
  end

  %w(
    glance-api
  ).each do |f|
    describe file "/etc/glance/#{f}.conf" do
      its('owner') { should eq 'root' }
      its('group') { should eq 'glance' }
      its('mode') { should cmp '0640' }
    end
  end

  describe ini('/etc/glance/glance-api.conf') do
    its('database.connection') { should cmp "mysql+pymysql://glance_x86:glance@#{db_endpoint}:3306/glance_x86" }
    its('DEFAULT.transport_url') { should cmp "rabbit://openstack:openstack@#{controller_endpoint}:5672" }
    its('rbd.rbd_store_pool') { should cmp 'images' } unless local_storage
    its('rbd.rbd_store_user') { should cmp 'glance' } unless local_storage
    its('keystone_authtoken.auth_url') { should cmp 'https://controller.example.com:5000/v3' }
    its('keystone_authtoken.memcached_servers') { should cmp "#{controller_endpoint}:11211" }
    its('keystone_authtoken.password') { should cmp 'glance' }
    its('keystone_authtoken.service_token_roles_required') { should cmp 'true' }
    its('keystone_authtoken.service_token_roles') { should cmp 'admin' }
    its('keystone_authtoken.www_authenticate_uri') { should cmp 'https://controller.example.com:5000/v3' }
  end

  describe command('/root/image_upload.sh') do
    its('exit_status') { should eq 0 }
  end

  describe command('bash -c "source /root/openrc && /usr/bin/openstack image list"') do
    its('stdout') do
      should match(/\|\s[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\s\|\scirros.*\s\|\sactive/)
    end
  end

  describe command('bash -c "source /root/openrc && /usr/bin/openstack image show cirros -c properties -f value"') do
    if local_storage
      its('stdout') { should_not match(/direct_url': 'rbd:/) }
      its('stdout') { should_not match(/'locations':/) }
    else
      its('stdout') { should match(/direct_url': 'rbd:/) }
      its('stdout') { should match(/'locations':/) }
    end
  end

  describe command('rbd --id glance ls images') do
    its('stdout') { should match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/) }
  end unless local_storage

  describe user('glance') do
    if local_storage
      its('groups') { should_not include 'ceph' }
    else
      its('groups') { should include 'ceph' }
    end
  end

  describe file('/etc/ceph/ceph.client.glance.keyring') do
    if local_storage
      it { should_not exist }
    else
      its('content') { should match(%r{key = [A-Za-z0-9+/].*==$}) }
      it { should be_owned_by 'ceph' }
      it { should be_grouped_into 'ceph' }
    end
  end
end
