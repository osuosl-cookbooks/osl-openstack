describe service('rabbitmq-server') do
  it { should be_enabled }
  it { should be_running }
end

%w(5672 15672).each do |p|
  describe port(p) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
  end
end

# Ensure we install the package from RDO
describe command('rpm -qi rabbitmq-server | grep Signature') do
  its('stdout') { should match(/Key ID f9b9fee7764429e6/) }
end

describe command('rabbitmqctl -q list_users') do
  its('stdout') { should match(/admin.*[administrator]/) }
end

describe command('curl -i -u admin:admin http://localhost:15672/api/whoami') do
  its('stdout') { should match(/{"name":"admin","tags":"administrator"}/) }
end
