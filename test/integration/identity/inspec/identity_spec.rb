describe service('httpd') do
  it { should be_enabled }
  it { should be_running }
end

%w(5000 35357).each do |p|
  describe port(p) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
    its('addresses') { should include '0.0.0.0' }
  end
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

describe apache_conf('/etc/httpd/sites-enabled/keystone-admin.conf') do
  its('<VirtualHost') { should include '0.0.0.0:35357>' }
end

describe apache_conf('/etc/httpd/sites-enabled/keystone-main.conf') do
  its('<VirtualHost') { should include '0.0.0.0:5000>' }
end

describe command("/opt/chef/embedded/bin/gem list -i -v '>= 0.2.0' fog-openstack") do
  its('stdout') { should match(/^false$/) }
end

describe command("/opt/chef/embedded/bin/gem list -i -v '< 0.2.0' fog-openstack") do
  its('stdout') { should match(/^true$/) }
end

describe command('grep -q deprecation /var/log/keystone/keystone.log') do
  its('exit_status') { should eq 1 }
end
