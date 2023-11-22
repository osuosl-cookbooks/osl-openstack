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
  openstack = 'bash -c "source /root/openrc && /usr/bin/openstack'

  describe command "#{openstack} volume create --size 1 test-volume\"" do
    its('exit_status') { should eq 0 }
  end

  describe command "#{openstack} volume delete test-volume\"" do
    its('exit_status') { should eq 0 }
  end
end
