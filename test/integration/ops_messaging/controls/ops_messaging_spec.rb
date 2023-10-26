control 'ops_messaging' do
  describe service('rabbitmq-server') do
    it { should be_enabled }
    it { should be_running }
  end

  describe port 5672 do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
  end

  describe iptables do
    it { should have_rule '-A amqp -p tcp -m tcp --dport 5672 -j osl_only' }
    it { should have_rule '-A rabbitmq_mgt -p tcp -m tcp --dport 15672 -j osl_only' }
  end

  # Ensure we install the package from RDO
  describe command('rpm -qi rabbitmq-server | grep Signature') do
    its('stdout') { should match(/Key ID f9b9fee7764429e6/) }
  end

  describe command('rabbitmqctl -q list_users') do
    its('stdout') { should match(/openstack.*\[\]/) }
  end
end
