%w(
  openstack-ceilometer-central
  openstack-ceilometer-notification
).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

describe service('openstack-ceilometer-collector') do
  it { should_not be_enabled }
  it { should_not be_running }
end

describe port(8041) do
  it { should be_listening }
  its('protocols') { should include 'tcp' }
  its('addresses') { should include '127.0.0.1' }
end

describe port(8777) do
  it { should_not be_listening }
  its('protocols') { should_not include 'tcp' }
  its('addresses') { should_not include '127.0.0.1' }
end

describe ini('/etc/ceilometer/ceilometer.conf') do
  its('DEFAULT.meter_dispatchers') { should_not cmp 'database' }
  its('api.default_api_return_limit') { should_not cmp '1000000000000' }
  its('DEFAULT.meter_dispatchers') { should cmp 'gnocchi' }
  its('api.host') { should cmp '127.0.0.1' }
  its('cache.memcache_servers') { should cmp 'controller.example.com:11211' }
  its('keystone_authtoken.memcached_servers') { should cmp 'controller.example.com:11211' }
  its('oslo_messaging_notifications.driver') { should cmp 'messagingv2' }
end

describe ini('/etc/gnocchi/gnocchi.conf') do
  its('keystone_authtoken.auth_url') { should cmp 'https://controller.example.com:5000/v3' }
  its('keystone_authtoken.password') { should cmp 'openstack-telemetry-metric' }
  its('storage.driver') { should cmp 'ceph' }
  its('storage.ceph_pool') { should cmp 'metrics' }
  its('storage.ceph_username') { should cmp 'gnocchi' }
  its('storage.ceph_keyring') { should cmp '/etc/ceph/ceph.client.gnocchi.keyring' }
  its('storage.file_basepath') { should_not cmp '/var/lib/gnocchi' }
  its('api.auth_mode') { should cmp 'keystone' }
  its('api.host') { should cmp '127.0.0.1' }
  its('database.connection') { should cmp 'mysql+pymysql://gnocchi_x86:gnocchi@controller.example.com:3306/gnocchi_x86?charset=utf8' }
  its('indexer.url') { should cmp 'mysql+pymysql://gnocchi_x86:gnocchi@controller.example.com:3306/gnocchi_x86?charset=utf8' }
end

describe user('gnocchi') do
  its('groups') { should include 'ceph' }
end

describe file('/usr/share/gnocchi/gnocchi-dist.conf') do
  its('mode') { should cmp '0644' }
end

describe command('bash -c "source /root/openrc && /usr/bin/openstack metric status -f shell"') do
  its('stdout') { should match(%r{^storage/number_of_metric_having_measures_to_process="0"$}) }
  its('stdout') { should match(%r{^storage/total_number_of_measures_to_process="0"$}) }
end

describe file('/etc/gnocchi/api-paste.ini') do
  its('content') { should match(/composite:gnocchi\+basic/) }
end

describe file('/etc/ceph/ceph.client.gnocchi.keyring') do
  its('content') { should match(%r{key = [A-Za-z0-9+/].*==$}) }
  it { should be_owned_by 'ceph' }
  it { should be_grouped_into 'ceph' }
end
