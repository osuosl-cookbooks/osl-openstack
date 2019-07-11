describe service('httpd') do
  it { should be_enabled }
  it { should be_running }
end

describe port(5000) do
  it { should be_listening }
  its('protocols') { should include 'tcp' }
  its('addresses') { should include '0.0.0.0' }
end

describe port(35357) do
  it { should_not be_listening }
  its('protocols') { should_not include 'tcp' }
  its('addresses') { should_not include '0.0.0.0' }
end

describe command('bash -c "source /root/openrc && /usr/bin/openstack token issue"') do
  its('stdout') { should match(/expires.*[0-9]{4}-[0-9]{2}-[0-9]{2}/) }
  its('stdout') { should match(/id\s*\|\s[0-9a-z]{32}/) }
  its('stdout') { should match(/project_id\s*\|\s[0-9a-z]{32}/) }
  its('stdout') { should match(/user_id\s*\|\s[0-9a-z]{32}/) }
end

describe ini('/etc/keystone/keystone.conf') do
  its('memcache.servers') { should cmp 'controller.example.com:11211' }
end

%w(keystone-admin.conf keystone-main.conf).each do |conf|
  describe file("/etc/httpd/sites-enabled/#{conf}") do
    it { should_not exist }
  end
end

describe apache_conf('/etc/httpd/sites-enabled/identity.conf') do
  its('<VirtualHost') { should include '0.0.0.0:5000>' }
end

describe command('grep -q deprecation /var/log/keystone/keystone.log') do
  its('exit_status') { should eq 1 }
end
