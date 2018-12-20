describe iptables do
  %w(
    127.0.0.1
    127.0.2.1
    127.0.3.1
  ).each do |ip|
    it { should have_rule("-A iscsi -s #{ip}/32 -p tcp -m tcp --dport 3260 -j ACCEPT") }
  end
end

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
cinder = 'bash -c "source /root/openrc && cinder '

describe command(cinder + ' create --display-name=test-volume 1"') do
  its('exit_status') { should eq 0 }
end

describe command(cinder + 'list"') do
  its('stdout') { should match(/test-volume/) }
end

describe command(cinder + 'delete test-volume"') do
  its('exit_status') { should eq 0 }
end
