require_controls 'osuosl-baseline' do
  control 'ssl-baseline'
end

control 'openstack-dashboard' do
  %w(80 443).each do |p|
    describe port(p) do
      it { should be_listening }
      its('protocols') { should include 'tcp' }
      its('addresses') { should include '::' }
    end
  end

  describe file('/etc/openstack-dashboard/local_settings') do
    its('content') { should match(/'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',/) }
    its('content') { match(/'LOCATION': \[\n\s*'controller.example.com:11211',/) }
    its('content') do
      should match(/
LAUNCH_INSTANCE_DEFAULTS = {
  'create_volume': False,
}/)
    end
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
