# describe command('bash -c "source /root/openrc && openstack server create --wait --image cirros --flavor m1.nano test"') do
#  its('exit_status') { should eq 0 }
#  its('stdout') { should match /OS-EXT-STS:vm_state.*active/ }
# end
#
# describe command('bash -c "source /root/openrc && openstack server image create --wait test"') do
#  its('exit_status') { should eq 0 }
# end
#
# describe command('bash -c "source /root/openrc && openstack image show -f shell test"') do
#  its('exit_status') { should eq 0 }
#  its('stdout') { should match /properties=.*image_type='snapshot'/ }
#  its('stdout') { should match /status="active"/ }
# end
#
# describe command('bash -c "source /root/openrc && openstack image delete test"') do
#  its('exit_status') { should eq 0 }
# end
#
# describe command('bash -c "source /root/openrc && openstack server delete --wait test"') do
#  its('exit_status') { should eq 0 }
# end
#
# describe command('bash -c "source /root/openrc && openstack stack create -t /tmp/heat.yml stack"') do
#  its('exit_status') { should eq 0 }
# end
#
# describe command('bash -c "source /root/openrc && openstack stack show stack -c stack_status -f value"') do
#  its('exit_status') { should eq 0 }
#  its('stdout') { should match(/^CREATE_IN_PROGRESS|CREATE_COMPLETE$/) }
# end
#
# describe command('bash -c "source /root/openrc && openstack stack delete -y  stack"') do
#  its('exit_status') { should eq 0 }
# end
