require_controls 'osuosl-baseline' do
  control 'ssl-baseline'
end

control 'openstack-dashboard' do
  describe package 'openstack-dashboard' do
    it { should be_installed }
  end

  %w(80 443).each do |p|
    describe port(p) do
      it { should be_listening }
      its('protocols') { should include 'tcp' }
      its('addresses') { should include '::' }
    end
  end

  describe file '/etc/httpd/conf.d/openstack-dashboard.conf' do
    it { should_not exist }
  end

  describe command 'systemctl cat httpd' do
    its('stdout') { should_not match /collectstatic/ }
  end

  describe file '/etc/openstack-dashboard/local_settings' do
    its('content') { should match(/^SECRET_KEY = '-#45g2\*o=8mhe\(10if%\*65@g#z0r#r7m__w6kwq8s9@n%12a11'$/) }
    its('content') { should match(%r{^OPENSTACK_KEYSTONE_URL = "https://controller\.example\.com:5000/"$}) }
    its('content') { should match(/'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',/) }
    its('content') { should match(/'LOCATION': \[\n\s*'controller.example.com:11211',/) }
    its('content') { should match(/LAUNCH_INSTANCE_DEFAULTS = {\n  'create_volume': False,\n}/) }
  end

  describe apache_conf('/etc/httpd/sites-enabled/horizon.conf') do
    its('ServerName') { should include 'controller.example.com' }
  end

  # Simulate logging into horizon with curl and test the output to ensure the
  # application is running correctly
  horizon_command =
    # 1. Get initial cookbooks for curl
    # 2. Grab the CSRF token
    # 3. Try logging into the site with the token
    'curl -so /dev/null -k -c c.txt -b c.txt https://localhost/auth/login/ && ' \
    'token=$(grep csrftoken c.txt | cut -f7) &&' \
    'curl -H \'Referer:https://localhost/auth/login/\' -k -c c.txt -b c.txt -d ' \
    '"login=admin&password=admin&csrfmiddlewaretoken=${token}" -v ' \
    'https://localhost/auth/login/ 2>&1'

  describe command(horizon_command) do
    its('stdout') { should match(/subject: CN=\*.example.com/) }
    its('stdout') { should match(/< HTTP.*200 OK/) }
    its('stdout') { should_not match(/CSRF verification failed. Request aborted./) }
  end
end
