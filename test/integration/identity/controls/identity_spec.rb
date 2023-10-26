require_controls 'osuosl-baseline' do
  control 'ssl-baseline'
end

control 'openstack-identity' do
  describe service('httpd') do
    it { should be_enabled }
    it { should be_running }
  end

  describe service('memcached') do
    it { should be_enabled }
    it { should be_running }
  end

  describe port(5000) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should include '::' }
  end

  describe port(11211) do
    it { should be_listening }
    its('protocols') { should include 'udp' }
    its('addresses') { should include '0.0.0.0' }
  end

  describe command('bash -c "source /root/openrc && /usr/bin/openstack token issue"') do
    its('stdout') { should match(/expires.*[0-9]{4}-[0-9]{2}-[0-9]{2}/) }
    its('stdout') { should match(/id\s*\|\s[0-9a-z]{32}/) }
    its('stdout') { should match(/project_id\s*\|\s[0-9a-z]{32}/) }
    its('stdout') { should match(/user_id\s*\|\s[0-9a-z]{32}/) }
  end

  describe file '/etc/keystone/keystone.conf' do
    its('owner') { should eq 'root' }
    its('group') { should eq 'keystone' }
    its('mode') { should cmp '0640' }
  end

  describe file '/etc/keystone/fernet-keys/0' do
    its('size') { should > 0 }
  end

  describe file '/etc/keystone/credential-keys/0' do
    its('size') { should > 0 }
  end

  describe ini('/etc/keystone/keystone.conf') do
    its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
  end

  describe apache_conf('/etc/httpd/sites-enabled/keystone.conf') do
    its('ServerName') { should include 'controller.example.com' }
  end
end
