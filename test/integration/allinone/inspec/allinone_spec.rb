describe command('bash -c "source /root/openrc && openstack stack create -t /tmp/heat.yml stack"') do
  its('exit_status') { should eq 0 }
end

describe command('bash -c "source /root/openrc && openstack stack show stack -c stack_status -f value"') do
  its('exit_status') { should eq 0 }
  its('stdout') { should match(/^CREATE_IN_PROGRESS|CREATE_COMPLETE$/) }
end

describe command('bash -c "source /root/openrc && openstack stack delete -y  stack"') do
  its('exit_status') { should eq 0 }
end

%w(
  check_cinder_api_v2
  check_cinder_api_v3
  check_glance_api
  check_keystone_api
  check_neutron_api
  check_neutron_floating_ip_public
  check_nova_api
).each do |check|
  describe command("/usr/lib64/nagios/plugins/check_nrpe -H localhost -c #{check}") do
    its('exit_status') { should eq 0 }
  end
end

describe command('bash -c "source /root/openrc && openstack server create --image cirros --flavor m1.nano test"') do
  its('exit_status') { should eq 0 }
  its('stdout') { should match /OS-EXT-STS:vm_state.*building/ }
end

describe command('bash -c "source /root/openrc && openstack server delete test"') do
  its('exit_status') { should eq 0 }
end
