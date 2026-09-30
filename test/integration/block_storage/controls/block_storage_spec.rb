control 'block-storage' do
  describe user('cinder') do
    its('groups') { should include 'ceph' }
  end

  %w(cinder cinder-backup).each do |key|
    describe file("/etc/ceph/ceph.client.#{key}.keyring") do
      it { should be_owned_by 'ceph' }
      it { should be_grouped_into 'ceph' }
      its('content') { should match(%r{key = [A-Za-z0-9+/].*==$}) }
    end
  end

  # Make sure we can create a volume, it exists and delete it
  openstack = ->(args) { %(bash -c "source /root/openrc && sleep 5 && /usr/bin/openstack #{args}") }

  describe command openstack.call('volume create --size 1 test-volume') do
    its('exit_status') { should eq 0 }
  end

  describe command openstack.call('volume delete test-volume') do
    its('exit_status') { should eq 0 }
  end
end

control 'block-storage-privsep' do
  # Rootwrap must accept privsep-helper and find it in the venv; it then fails for want of a socket
  describe command('runuser -u cinder -- sudo -n /usr/bin/cinder-rootwrap /etc/cinder/rootwrap.conf privsep-helper ' \
                   '--config-file /etc/cinder/cinder.conf --privsep_context os_brick.privileged.default ' \
                   '--privsep_sock_path /tmp/inspec-privsep') do
    its('stderr') { should_not match(/Unauthorized command|Executable not found|password is required/) }
    its('stdout') { should_not match(/Unauthorized command|Executable not found/) }
  end
end
