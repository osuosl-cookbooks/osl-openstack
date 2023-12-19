prometheus_endpoint = input('prometheus_endpoint')
python_ver = os.release.to_i == 7 ? 'python2.7' : 'python3.6'

control 'telemetry-controller' do
  %w(
    openstack-ceilometer-central
    openstack-ceilometer-common
    openstack-ceilometer-notification
    patch
  ).each do |p|
    describe package p do
      it { should be_installed }
    end
  end

  %w(
    openstack-ceilometer-central
    openstack-ceilometer-notification
  ).each do |s|
    describe service s do
      it { should be_enabled }
      it { should be_running }
    end
  end

  describe file '/etc/ceilometer/pipeline.yaml' do
    its('content') { should match %r{publishers:\n\s+- prometheus://#{prometheus_endpoint}:9091/metrics/job/ceilometer} }
  end

  describe ini('/etc/ceilometer/ceilometer.conf') do
    its('DEFAULT.transport_url') { should cmp 'rabbit://openstack:openstack@controller.example.com:5672' }
    its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
    its('service_credentials.auth_url') { should cmp 'https://controller.example.com:5000/v3' }
    its('service_credentials.password') { should cmp 'ceilometer' }
  end

  describe file "/usr/lib/#{python_ver}/site-packages/ceilometer/publisher/prometheus.py" do
    its('content') { should match /curated_sname/ }
    its('content') { should match /s\.project_id/ }
  end

  describe http('http://localhost:9091/metrics') do
    its('body') { should match /^image_size{instance="",job="ceilometer",project_id="/ }
  end
end
