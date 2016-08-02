require 'serverspec'

set :backend, :exec

describe service('rabbitmq-server') do
  it { should be_enabled }
  it { should be_running }
end

%w(5672 15672).each do |p|
  describe port(p) do
    it { should be_listening.with('tcp') }
  end
end

describe command('rabbitmqctl -q list_users') do
  its(:stdout) { should contain(/admin.*[administrator]/) }
end

describe command('curl -i -u admin:admin http://localhost:15672/api/whoami') do
  its(:stdout) { should contain(/{"name":"admin","tags":"administrator"}/) }
end
