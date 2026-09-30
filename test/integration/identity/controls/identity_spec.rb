require_controls 'osuosl-baseline' do
  control 'ssl-baseline'
end unless input('skip_ssl_baseline')

db_endpoint = input('db_endpoint')
# messaging_host = AMQP host (mq tier on multi-node); memcached_host =
# the memcached backend (controller1 on multi-node).
messaging_host = input('messaging_host')
messaging_port = input('messaging_port')
memcached_host = input('memcached_host')

control 'openstack-identity' do
  openstack = ->(args) { %(bash -c "source /root/openrc && /usr/bin/openstack #{args}") }

  describe package 'osuosl-openstack-keystone' do
    it { should be_installed }
  end

  describe package 'osuosl-openstack-cli' do
    it { should be_installed }
  end

  # httpd proxies to keystone-uwsgi's socket
  %w(httpd keystone-uwsgi).each do |s|
    describe service(s) do
      it { should be_enabled }
      it { should be_running }
    end
  end

  describe user('keystone') do
    its('group') { should eq 'keystone' }
    its('groups') { should include 'apache' }
  end

  describe directory '/etc/keystone' do
    its('owner') { should eq 'root' }
    its('group') { should eq 'keystone' }
    its('mode') { should cmp '0750' }
  end

  describe file '/etc/keystone/keystone-uwsgi.ini' do
    its('owner') { should eq 'root' }
    its('group') { should eq 'keystone' }
    its('mode') { should cmp '0640' }
  end

  describe ini '/etc/keystone/keystone-uwsgi.ini' do
    its('uwsgi.socket') { should cmp '/run/keystone/uwsgi.sock' }
    its('uwsgi.uid') { should cmp 'keystone' }
    its('uwsgi.wsgi-file') { should cmp '/opt/openstack/keystone/bin/keystone-wsgi-public' }
  end

  describe file '/run/keystone/uwsgi.sock' do
    it { should be_socket }
    its('owner') { should eq 'keystone' }
    its('group') { should eq 'apache' }
  end

  describe json(
    content: http('https://controller.testing.osuosl.org:5000/identity/v3', ssl_verify: false).body
  ) do
    its(%w(version status)) { should cmp 'stable' }
  end

  describe service('memcached') do
    it { should be_enabled }
    it { should be_running }
  end

  describe port(11211) do
    it { should be_listening }
    its('processes') { should include 'memcached' }
    its('protocols') { should include 'tcp' }
    its('protocols') { should include 'udp' }
  end

  # osl_only jumps to the OSL CIDR chain; loopback is accepted separately.
  # This also covers the peer controller in HA.
  describe iptables do
    it { should have_rule('-A memcached -p tcp -m tcp --dport 11211 -j osl_only') }
    it { should have_rule('-A memcached -p udp -m udp --dport 11211 -j osl_only') }
  end

  describe ip6tables do
    it { should have_rule('-A memcached -p tcp -m tcp --dport 11211 -j osl_only') }
    it { should have_rule('-A memcached -p udp -m udp --dport 11211 -j osl_only') }
  end

  # Prometheus exporter scrapes localhost:11211 and reports up=1.
  describe http('http://localhost:9150/metrics') do
    its('status') { should cmp 200 }
    its('body') { should match(/memcached_up 1/) }
  end

  describe port(5000) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
  end

  describe json(
    content: http(
      'https://controller.testing.osuosl.org:5000/v3',
      ssl_verify: false
    ).body
  ) do
    its(%w(version status)) { should cmp 'stable' }
  end

  # The canonical-host 301 is off behind haproxy, where it would loop;
  # keystone answers with its 300 version discovery there instead.
  unless input('haproxy_tls')
    describe http(
      'https://controller.testing.osuosl.org:5000',
      headers: { 'Host' => 'controller1.testing.osuosl.org' },
      ssl_verify: false
    ) do
      its('status') { should cmp 301 }
      its('headers.location') { should cmp 'https://controller.testing.osuosl.org:5000/' }
    end
  end

  describe command(openstack.call('token issue')) do
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
    its('DEFAULT.public_endpoint') { should cmp 'https://controller.testing.osuosl.org:5000/' }
    its('DEFAULT.transport_url') { should match(%r{^rabbit://openstack:openstack@#{Regexp.escape(messaging_host)}:#{messaging_port}}) }
    its('cache.memcache_servers') { should match(/#{Regexp.escape(memcached_host)}:11211/) }
    its('database.connection') { should cmp "mysql+pymysql://keystone_x86:keystone@#{db_endpoint}:3306/keystone_x86" }
    its('database.connection_recycle_time') { should cmp 300 }
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
    its('ServerName') { should include 'controller.testing.osuosl.org' }
  end
end
