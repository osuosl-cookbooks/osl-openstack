# The jumphost found the multinode cloud by node search and can reach every host as root
control 'upgrade-runner' do
  describe json('/etc/openstack-upgrade/multinode.json') do
    its('controllers') { should eq %w(controller1.testing.osuosl.org controller2.testing.osuosl.org) }
    its('db_node') { should eq 'controller1.testing.osuosl.org' }
    its(%w(hypervisors 0 fqdn)) { should eq 'compute.testing.osuosl.org' }
    its('canaries') { should eq %w(compute.testing.osuosl.org) }
  end

  describe file('/usr/local/sbin/openstack-upgrade') do
    its('mode') { should cmp '0755' }
  end

  describe command('/usr/local/sbin/openstack-upgrade multinode status') do
    its('exit_status') { should eq 0 }
    its('stdout') { should match /^controller1\.testing\.osuosl\.org\s+installed=yoga/ }
    its('stdout') { should match /^compute\.testing\.osuosl\.org\s+installed=yoga/ }
  end
end
