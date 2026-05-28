require_controls 'osuosl-baseline' do
  control 'ssl-baseline'
end unless input('skip_ssl_baseline', value: false)

db_endpoint = input('db_endpoint')
# RabbitMQ / memcached cluster member that appears in transport_url and
# memcache_servers. Single-controller: the cloud name. HA multi-node:
# the first controller (controller1), distinct from the VIP that
# controller_endpoint / the public endpoints resolve to.
messaging_host = input('messaging_host', value: 'controller.testing.osuosl.org')

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

  describe port(11211) do
    it { should be_listening }
    its('processes') { should include 'memcached' }
    its('protocols') { should include 'tcp' }
    its('protocols') { should include 'udp' }
  end

  # osl_memcached uses `osl_only: true`: the memcached chain jumps to
  # the OSL CIDR chain (no -s rule). Local nc still works because
  # osl-firewall accepts all lo traffic via the 20_loopback chain.
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

  # The wsgi-keystone canonical-host rewrite (Host !~ server_name ->
  # 301 to https://server_name:5000/) is gated off when haproxy
  # terminates TLS: behind the VIP the rewrite would 301 healthchecks
  # and internal traffic into a loop. In HA, keystone itself answers
  # with its 300 version-discovery payload instead.
  unless input('haproxy_tls', value: false)
    describe http(
      'https://controller.testing.osuosl.org:5000',
      headers: { 'Host' => 'controller1.testing.osuosl.org' },
      ssl_verify: false
    ) do
      its('status') { should cmp 301 }
      its('headers.location') { should cmp 'https://controller.testing.osuosl.org:5000/' }
    end
  end

  describe port(11211) do
    it { should be_listening }
    its('protocols') { should include 'udp' }
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
    its('DEFAULT.public_endpoint') { should cmp 'https://controller.testing.osuosl.org:5000/' }
    its('DEFAULT.transport_url') { should match(%r{^rabbit://openstack:openstack@#{Regexp.escape(messaging_host)}:5672}) }
    its('cache.memcache_servers') { should match(/#{Regexp.escape(messaging_host)}:11211/) }
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
    its('ServerName') { should include 'controller.testing.osuosl.org' }
  end
end
