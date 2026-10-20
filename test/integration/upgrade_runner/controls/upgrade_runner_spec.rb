# Read on the workstation: how many computes terraform built, as kitchen.multi-node.yml counts them
computes = (ENV['TF_VAR_computes'] || '1').to_i
hypervisors = Array.new(computes) { |i| "#{i.zero? ? 'compute' : "compute#{i + 1}"}.testing.osuosl.org" }

# The jumphost found the multinode cloud by node search and can reach every host as root
control 'upgrade-runner' do
  inventory = json('/etc/openstack-upgrade/multinode.json')

  describe inventory do
    its('controllers') { should eq %w(controller1.testing.osuosl.org controller2.testing.osuosl.org) }
    its('db_node') { should eq 'controller1.testing.osuosl.org' }
    its('canaries') { should eq hypervisors.first(1) }
  end

  describe Array(inventory.params['hypervisors']).map { |h| h['fqdn'] } do
    it { should eq hypervisors }
  end

  describe file('/usr/local/sbin/openstack-upgrade') do
    its('mode') { should cmp '0755' }
  end

  describe command('/usr/local/sbin/openstack-upgrade --help') do
    its('exit_status') { should eq 0 }
    its('stdout') { should match /\{status,rollback,.*upgrade.*\}/ }
  end

  describe command('/usr/local/sbin/openstack-upgrade multinode status') do
    its('exit_status') { should eq 0 }
    its('stdout') { should match /^controller1\.testing\.osuosl\.org\s+installed=\S+/ }
    hypervisors.each do |fqdn|
      its('stdout') { should match /^#{Regexp.escape(fqdn)}\s+installed=\S+/ }
    end
  end
end
