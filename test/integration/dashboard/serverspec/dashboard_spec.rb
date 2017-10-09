require 'serverspec'

set :backend, :exec

%w(80 443).each do |p|
  describe port(p) do
    it { should be_listening.with('tcp') }
  end
end

describe file('/etc/openstack-dashboard/local_settings') do
  its(:content) do
    should contain(/'BACKEND': 'django.core.cache.backends.memcached.\
MemcachedCache',/)
  end
  its(:content) do
    should contain(/'LOCATION': \[\n\s*'.*:11211',/)
  end
  its(:content) do
    should match(/
LAUNCH_INSTANCE_DEFAULTS = {
  'create_volume': 'false',
  'disable_volume': 'true',
  'disable_volume_snapshot': 'true',
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
  its(:stdout) { should contain(/subject: CN=\*.example.com/) }
  its(:stdout) { should contain(/< HTTP.*200 OK/) }
  its(:stdout) do
    should_not contain(/CSRF verification failed. Request aborted./)
  end
end
