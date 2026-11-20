control 'controller' do
  %w(
    check_cinder_api
    check_glance_api
    check_heat_api
    check_keystone_api
    check_neutron_api
    check_nova_api
    check_nova_placement_api
    check_novnc
  ).each do |check|
    describe command("/usr/lib64/nagios/plugins/check_nrpe -H localhost -c #{check}") do
      its('exit_status') { should eq 0 }
    end
  end
end

control 'netns-conntrack' do
  title 'Each network namespace conntrack count reaches node_exporter every minute'
  describe crontab(user: 'root').commands('/usr/local/libexec/openstack-netns-conntrack') do
    its('minutes') { should cmp '*' }
  end
  # Run it as cron does: root's crontab PATH has no /usr/sbin
  describe command('env -i PATH=/usr/bin:/bin /usr/local/libexec/openstack-netns-conntrack') do
    its('exit_status') { should eq 0 }
    its('stderr') { should eq '' }
  end
  describe file('/var/lib/node_exporter/openstack_netns_conntrack.prom') do
    its('content') { should match(/^# TYPE openstack_netns_conntrack_entries gauge$/) }
    its('content') { should match(/^openstack_netns_conntrack_last_success_timestamp_seconds \d{10}$/) }
    its('mode') { should cmp '0644' }
  end
end

control 'netns-conntrack-qdhcp' do
  title 'A DHCP namespace shows up in the conntrack gauge'
  only_if('no qdhcp namespace on this node') { command('ip netns list').stdout.match?(/^qdhcp-/) }
  describe file('/var/lib/node_exporter/openstack_netns_conntrack.prom') do
    its('content') { should match(/^openstack_netns_conntrack_entries\{netns="qdhcp-[0-9a-f-]+"\} \d+$/) }
  end
end
