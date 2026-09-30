control 'boot-instance' do
  describe command('timeout 900 /root/boot_instance.sh') do
    its('exit_status') { should eq 0 }
    its('stdout') { should match(/^ACTIVE$/) }
  end

  describe command('bash -c "source /root/openrc && openstack server delete --wait boot-test"') do
    its('exit_status') { should eq 0 }
  end
end
