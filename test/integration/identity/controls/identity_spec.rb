require_controls 'osuosl-baseline' do
  control 'ssl-baseline'
end

db_endpoint = input('db_endpoint')
os_release = os.release.to_i

control 'openstack-identity' do
  describe package 'openstack-keystone' do
    it { should be_installed }
  end

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
    case os_release
    when 7
      its('addresses') { should include '::' }
    when 8
      its('addresses') { should include '0.0.0.0' }
    end
  end

  describe json(
    content: http(
      'https://127.0.0.1:5000/v3',
      headers: { 'Host' => 'controller.example.com' },
      ssl_verify: false
    ).body
  ) do
    its(%w(version status)) { should cmp 'stable' }
  end

  describe http(
    'https://127.0.0.1:5000',
    headers: { 'Host' => 'controller1.example.com' },
    ssl_verify: false
  ) do
    its('status') { should cmp 301 }
    its('headers.location') { should cmp 'https://controller.example.com:5000/' }
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

  describe ini '/etc/keystone/keystone.conf' do
    its('DEFAULT.public_endpoint') { should cmp 'https://controller.example.com:5000/' }
    its('DEFAULT.transport_url') { should cmp 'rabbit://openstack:openstack@controller.example.com:5672' }
    its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
    its('database.connection') { should cmp "mysql+pymysql://keystone_x86:keystone@#{db_endpoint}:3306/keystone_x86" }
  end

  %w(
    credential-keys
    fernet-keys
  ).each do |k|
    %w(0 1).each do |i|
      describe file "/etc/keystone/#{k}/#{i}" do
        its('owner') { should eq 'keystone' }
        its('group') { should eq 'keystone' }
        its('mode') { should cmp '0600' }
        its('size') { should > 0 }
      end
    end
  end

  describe file '/etc/keystone/bootstrapped' do
    it { should exist }
  end

  describe apache_conf('/etc/httpd/sites-enabled/keystone.conf') do
    its('ServerName') { should include 'controller.example.com' }
  end
end
