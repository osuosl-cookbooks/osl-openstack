describe package('nagios-plugins-openstack') do
  it { should_not be_installed }
end

describe file('/usr/lib64/nagios/plugins/check_openstack') do
  its('content') { should match(%r{/usr/lib64/nagios/plugins/\$\{@\}}) }
  its('mode') { should cmp '0755' }
end

describe file('/etc/sudoers.d/nrpe-openstack') do
  its('content') do
    should match(%r{%nrpe ALL=\(root\) NOPASSWD:/usr/lib64/nagios/plugins/check_openstack})
  end
end

%w(
  check_cinder_api
  check_cinder_services
  check_neutron_agents
  check_neutron_floating_ip
  check_nova_hypervisors
  check_nova_images
  check_nova_services
).each do |check|
  describe file("/etc/nagios/nrpe.d/#{check}.cfg") do
    it { should_not exist }
  end
end

%w(
  check_glance_api
  check_keystone_api
  check_neutron_api
).each do |check|
  describe file("/etc/nagios/nrpe.d/#{check}.cfg") do
    its('content') do
      should match(%r{command\[#{check}\]=/bin/sudo /usr/lib64/nagios/plugins/check_openstack #{check}$})
    end
  end
end

describe file('/etc/nagios/nrpe.d/check_nova_api.cfg') do
  its('content') do
    should match(%r{command\[check_nova_api\]=/bin/sudo /usr/lib64/nagios/plugins/check_openstack check_nova_api --os-compute-api-version 2$})
  end
end

describe file('/etc/nagios/nrpe.d/check_cinder_api_v2.cfg') do
  its('content') do
    should match(%r{command\[check_cinder_api_v2\]=/bin/sudo /usr/lib64/nagios/plugins/check_openstack check_cinder_api --os-volume-api-version 2$})
  end
end

describe file('/etc/nagios/nrpe.d/check_cinder_api_v3.cfg') do
  its('content') do
    should match(%r{command\[check_cinder_api_v3\]=/bin/sudo /usr/lib64/nagios/plugins/check_openstack check_cinder_api --os-volume-api-version 3$})
  end
end

describe file('/etc/nagios/nrpe.d/check_neutron_floating_ip_public.cfg') do
  its('content') do
    should match(%r{command\[check_neutron_floating_ip_public\]=/bin/sudo /usr/lib64/nagios/plugins/check_openstack check_neutron_floating_ip --ext_network_name public$})
  end
end

describe file '/usr/local/etc/os_cluster' do
  its('content') { should cmp "export OS_CLUSTER=x86\n" }
end

describe gem('prometheus_reporter', '/opt/cinc/embedded/bin/gem') do
  it { should be_installed }
end

describe file '/usr/local/libexec/openstack-prometheus' do
  it { should be_executable }
end

describe file '/usr/local/libexec/openstack-prometheus.rb' do
  it { should be_executable }
end

describe crontab 'root' do
  its('commands') { should include '/usr/local/libexec/openstack-prometheus' }
  its('minutes') { should cmp '*/10' }
end
