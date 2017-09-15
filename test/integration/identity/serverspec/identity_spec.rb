require 'serverspec'

set :backend, :exec

describe service('httpd') do
  it { should be_enabled }
  it { should be_running }
end

%w(5000 35357).each do |p|
  describe port(p) do
    it { should be_listening.with('tcp') }
  end
end

describe command('source /root/openrc && /usr/local/bin/openstack token issue') do
  its(:stdout) { should contain(/expires.*[0-9]{4}-[0-9]{2}-[0-9]{2}/) }
  its(:stdout) { should contain(/id\s*\|\s[0-9a-z]{32}/) }
  its(:stdout) { should contain(/project_id\s*\|\s[0-9a-z]{32}/) }
  its(:stdout) { should contain(/user_id\s*\|\s[0-9a-z]{32}/) }
end

describe file('/etc/keystone/keystone.conf') do
  its(:content) { should contain(/\[memcache\]\nservers = .*:11211/) }
end

describe file('/etc/httpd/sites-enabled/keystone-admin.conf') do
  its(:content) { should contain(/<VirtualHost 0.0.0.0:35357>/) }
end

describe file('/etc/httpd/sites-enabled/keystone-main.conf') do
  its(:content) { should contain(/<VirtualHost 0.0.0.0:5000>/) }
end
