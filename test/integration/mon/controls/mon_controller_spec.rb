ip_address = inspec.interfaces.ipv4_address

control 'mon' do
  describe file('/etc/nagios/nrpe.d/check_cinder_api.cfg') do
    its('content') do
      should match(%r{command\[check_cinder_api\]=/usr/lib64/nagios/plugins/check_http -I #{ip_address} -p 8776})
    end
  end

  describe file('/etc/nagios/nrpe.d/check_heat_api.cfg') do
    its('content') do
      should match %r{command\[check_heat_api\]=/usr/lib64/nagios/plugins/check_http -I #{ip_address} -p 8004}
    end
  end

  describe file('/etc/nagios/nrpe.d/check_keystone_api.cfg') do
    its('content') do
      should match %r{command\[check_keystone_api\]=/usr/lib64/nagios/plugins/check_http --ssl -I #{ip_address} -p 5000}
    end
  end

  describe file('/etc/nagios/nrpe.d/check_neutron_api.cfg') do
    its('content') do
      should match %r{command\[check_neutron_api\]=/usr/lib64/nagios/plugins/check_http -I #{ip_address} -p 9696}
    end
  end

  describe file('/etc/nagios/nrpe.d/check_nova_api.cfg') do
    its('content') do
      should match %r{command\[check_nova_api\]=/usr/lib64/nagios/plugins/check_http -I #{ip_address} -p 8774}
    end
  end

  describe file('/etc/nagios/nrpe.d/check_nova_placement_api.cfg') do
    its('content') do
      should match %r{command\[check_nova_placement_api\]=/usr/lib64/nagios/plugins/check_http -I #{ip_address} -p 8778}
    end
  end

  describe file('/etc/nagios/nrpe.d/check_novnc.cfg') do
    its('content') do
      should match %r{command\[check_novnc\]=/usr/lib64/nagios/plugins/check_http --ssl -I #{ip_address} -p 6080}
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

  describe crontab('root').commands('/usr/local/libexec/openstack-prometheus') do
    its('commands') { should include '/usr/local/libexec/openstack-prometheus' }
    its('minutes') { should cmp '*/10' }
  end
end
