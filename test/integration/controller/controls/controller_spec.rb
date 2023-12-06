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
