require 'serverspec'

set :backend, :exec

%w(
  127.0.0.1
  127.0.2.1
  127.0.3.1
).each do |ip|
  describe iptables do
    it do
      should have_rule("-A iscsi -s #{ip}/32 -p tcp -m tcp --dport 3260 -j
ACCEPT")
    end
  end
end

# Make sure we can create a volume, it exists and delete it
cinder = 'source /root/openrc && cinder '

describe command(cinder + ' create --display-name=test-volume 1') do
  its(:exit_status) { should eq 0 }
end

describe command(cinder + 'list') do
  its(:stdout) { should match /test-volume/ }
end

describe command(cinder + 'delete test-volume') do
  its(:exit_status) { should eq 0 }
end
