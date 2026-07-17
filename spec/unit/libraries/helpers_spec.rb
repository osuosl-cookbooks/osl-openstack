require_relative '../../spec_helper'
require 'chef/data_bag_item'
require 'chef/encrypted_data_bag_item'
require_relative '../../../libraries/helpers'

describe OSLOpenstack::Cookbook::Helpers do
  # safe_dig is a private instance method on the helper module. Build a
  # throwaway including-class so we can call it through `send`.
  let(:helper) do
    Class.new { include OSLOpenstack::Cookbook::Helpers }.new
  end

  def safe_dig(*args)
    helper.send(:safe_dig, *args)
  end

  describe '#safe_dig' do
    it 'walks a plain Hash to a leaf' do
      expect(safe_dig({ 'a' => { 'b' => 'c' } }, 'a', 'b')).to eq('c')
    end

    it 'returns nil when a key is missing' do
      expect(safe_dig({ 'a' => {} }, 'a', 'missing')).to be_nil
    end

    it 'returns nil when an intermediate value is not Hash-like' do
      expect(safe_dig({ 'a' => 'leaf-string' }, 'a', 'b')).to be_nil
    end

    it 'walks a Chef::DataBagItem' do
      item = Chef::DataBagItem.new
      item.raw_data = { 'id' => 'x', 'ha' => { 'vip_v4' => '10.0.0.1' } }
      expect(safe_dig(item, 'ha', 'vip_v4')).to eq('10.0.0.1')
    end

    # Regression: safe_dig used to only match Hash and Chef::DataBagItem.
    # Chef's DSL returns Chef::EncryptedDataBagItem (a separate sibling
    # class, NOT a DataBagItem subclass) when the bag is encrypted, so
    # the old type check silently returned nil on encrypted bags - the
    # `if safe_dig(os_secrets, 'ha')` gate in controller.rb stayed false
    # in production even after the data bag was updated.
    it 'walks a Chef::EncryptedDataBagItem' do
      secret = 'a' * 32
      enc_hash = {
        'id' => 'x',
        'ha' => Chef::EncryptedDataBagItem::Encryptor.new(
          { 'vip_v4' => '10.0.0.1' },
          secret
        ).for_encrypted_item,
      }
      item = Chef::EncryptedDataBagItem.new(enc_hash, secret)
      expect(safe_dig(item, 'ha', 'vip_v4')).to eq('10.0.0.1')
    end
  end

  describe '#openstack_local_api_endpoint' do
    let(:fqdn) { 'controller1.testing.osuosl.org' }

    before do
      allow(helper).to receive(:node).and_return(
        'fqdn' => fqdn,
        'ipaddress' => '10.0.0.2'
      )
    end

    it 'returns the per-host api_listen_ip when HA is configured' do
      allow(helper).to receive(:os_secrets).and_return(
        'ha' => { 'api_listen_ip' => { fqdn => '10.1.2.3' } }
      )
      expect(helper.openstack_local_api_endpoint).to eq('10.1.2.3')
    end

    it "falls back to node['ipaddress'] when HA isn't configured" do
      allow(helper).to receive(:os_secrets).and_return({})
      expect(helper.openstack_local_api_endpoint).to eq('10.0.0.2')
    end

    it "falls back to node['ipaddress'] when this node has no api_listen_ip entry" do
      allow(helper).to receive(:os_secrets).and_return(
        'ha' => { 'api_listen_ip' => { 'other.fqdn' => '10.1.2.99' } }
      )
      expect(helper.openstack_local_api_endpoint).to eq('10.0.0.2')
    end
  end

  describe '#openstack_tls_on_haproxy?' do
    it 'returns false when the ha block is absent' do
      allow(helper).to receive(:os_secrets).and_return({})
      expect(helper.openstack_tls_on_haproxy?).to be false
    end

    it 'returns true when the ha block is present' do
      allow(helper).to receive(:os_secrets).and_return(
        'ha' => { 'keepalived' => {} }
      )
      expect(helper.openstack_tls_on_haproxy?).to be true
    end
  end

  describe '#openstack_rabbit_quorum_queue?' do
    it 'returns false when messaging.quorum_queues is absent' do
      allow(helper).to receive(:os_secrets).and_return('messaging' => {})
      expect(helper.openstack_rabbit_quorum_queue?).to be false
    end

    it 'returns true when messaging.quorum_queues is set' do
      allow(helper).to receive(:os_secrets).and_return(
        'messaging' => { 'quorum_queues' => true }
      )
      expect(helper.openstack_rabbit_quorum_queue?).to be true
    end
  end

  describe '#openstack_rabbit_tls?' do
    it 'returns false when messaging.tls is absent' do
      allow(helper).to receive(:os_secrets).and_return('messaging' => {})
      expect(helper.openstack_rabbit_tls?).to be false
    end

    it 'returns true when messaging.tls is set' do
      allow(helper).to receive(:os_secrets).and_return('messaging' => { 'tls' => true })
      expect(helper.openstack_rabbit_tls?).to be true
    end
  end

  describe '#openstack_rabbit_ssl_ca_file' do
    it 'returns nil when unset (oslo falls back to the system trust store)' do
      allow(helper).to receive(:os_secrets).and_return('messaging' => {})
      expect(helper.openstack_rabbit_ssl_ca_file).to be_nil
    end

    it 'returns the configured path' do
      allow(helper).to receive(:os_secrets).and_return(
        'messaging' => { 'ssl_ca_file' => '/etc/pki/tls/certs/osl-chain.pem' }
      )
      expect(helper.openstack_rabbit_ssl_ca_file).to eq('/etc/pki/tls/certs/osl-chain.pem')
    end
  end

  describe '#openstack_rabbitmq_join_needed?' do
    let(:primary) { 'rabbit@mq1.bak.osuosl.org' }

    def stub_cluster_status(stdout)
      status = double(stdout: stdout)
      allow(status).to receive(:error!)
      allow(helper).to receive(:shell_out).with('rabbitmqctl cluster_status').and_return(status)
    end

    it 'is false on the primary itself (multi-label domain -> short hostname)' do
      allow(helper).to receive(:node).and_return('hostname' => 'mq1')
      expect(helper).to_not receive(:shell_out)
      expect(helper.openstack_rabbitmq_join_needed?(primary)).to be false
    end

    it 'is false on a secondary already clustered with the primary' do
      allow(helper).to receive(:node).and_return('hostname' => 'mq2')
      stub_cluster_status("Running Nodes\n\nrabbit@mq1.bak.osuosl.org\nrabbit@mq2.bak.osuosl.org\n")
      expect(helper.openstack_rabbitmq_join_needed?(primary)).to be false
    end

    it 'is true on an unclustered secondary' do
      allow(helper).to receive(:node).and_return('hostname' => 'mq2')
      stub_cluster_status("Running Nodes\n\nrabbit@mq2.bak.osuosl.org\n")
      expect(helper.openstack_rabbitmq_join_needed?(primary)).to be true
    end

    it 'does not conflate the primary hostname with one it prefixes' do
      allow(helper).to receive(:node).and_return('hostname' => 'mq10')
      stub_cluster_status("Running Nodes\n\nrabbit@mq10.bak.osuosl.org\n")
      expect(helper.openstack_rabbitmq_join_needed?(primary)).to be true
    end
  end

  describe '#openstack_transport_url' do
    let(:messaging) do
      { 'user' => 'openstack', 'pass' => 's3cret',
        'endpoint' => ['mq2.example.org', 'mq1.example.org', 'mq3.example.org'] }
    end

    it 'sorts endpoints, uses :5672, and the default vhost (empty path)' do
      allow(helper).to receive(:os_secrets).and_return('messaging' => messaging)
      expect(helper.openstack_transport_url).to eq(
        'rabbit://openstack:s3cret@mq1.example.org:5672,' \
        'openstack:s3cret@mq2.example.org:5672,' \
        'openstack:s3cret@mq3.example.org:5672/'
      )
    end

    it 'renders a named vhost as the URL path and uses :5671 under TLS' do
      allow(helper).to receive(:os_secrets).and_return(
        'messaging' => messaging.merge('vhost' => 'x86', 'tls' => true)
      )
      expect(helper.openstack_transport_url).to eq(
        'rabbit://openstack:s3cret@mq1.example.org:5671,' \
        'openstack:s3cret@mq2.example.org:5671,' \
        'openstack:s3cret@mq3.example.org:5671/x86'
      )
    end

    it "treats an explicit '/' vhost as the default (empty path)" do
      allow(helper).to receive(:os_secrets).and_return(
        'messaging' => messaging.merge('vhost' => '/')
      )
      expect(helper.openstack_transport_url).to end_with(':5672/')
    end
  end

  describe '#haproxy_running?' do
    it 'is true when systemctl is-active exits 0' do
      shellout = instance_double(Mixlib::ShellOut, exitstatus: 0)
      allow(helper).to receive(:shell_out)
        .with('systemctl is-active --quiet haproxy').and_return(shellout)
      expect(helper.haproxy_running?).to be true
    end

    it 'is false when systemctl is-active exits non-zero' do
      shellout = instance_double(Mixlib::ShellOut, exitstatus: 3)
      allow(helper).to receive(:shell_out)
        .with('systemctl is-active --quiet haproxy').and_return(shellout)
      expect(helper.haproxy_running?).to be false
    end

    it 'is false (not raising) when systemctl is unavailable' do
      allow(helper).to receive(:shell_out).and_raise(Errno::ENOENT)
      expect(helper.haproxy_running?).to be false
    end
  end

  describe '#openstack_keystone_reachable?' do
    before do
      allow(helper).to receive(:os_secrets)
        .and_return('identity' => { 'endpoint' => 'controller.testing.osuosl.org' })
    end

    it 'is true when a TCP connect to the VIP:5000 succeeds' do
      socket = instance_double(TCPSocket, close: nil)
      allow(TCPSocket).to receive(:new)
        .with('controller.testing.osuosl.org', 5000).and_return(socket)
      expect(helper.openstack_keystone_reachable?).to be true
    end

    it 'is false (not raising) when the VIP is unreachable' do
      allow(TCPSocket).to receive(:new).and_raise(Errno::EHOSTUNREACH)
      expect(helper.openstack_keystone_reachable?).to be false
    end
  end

  describe '#openstack_wait_for_keystone' do
    before do
      allow(helper).to receive(:os_secrets)
        .and_return('identity' => { 'endpoint' => 'controller.testing.osuosl.org' })
      allow(helper).to receive(:sleep)
    end

    it 'returns once keystone becomes reachable' do
      allow(helper).to receive(:openstack_keystone_reachable?)
        .and_return(false, false, true)
      expect { helper.openstack_wait_for_keystone }.not_to raise_error
    end

    it 'raises after exhausting the attempt budget' do
      allow(helper).to receive(:openstack_keystone_reachable?).and_return(false)
      expect { helper.openstack_wait_for_keystone }.to raise_error(/unreachable after/)
    end
  end

  describe '#openstack_ha_services' do
    let(:services) { helper.openstack_ha_services }

    it 'marks the services that already serve TLS today' do
      tls_services = services.select { |s| s[:tls] }.map { |s| s[:name] }
      expect(tls_services).to contain_exactly(
        'keystone', 'novnc', 'horizon-https'
      )
    end

    it 'leaves the http endpoints unmarked' do
      plain_services = services.reject { |s| s[:tls] }.map { |s| s[:name] }
      expect(plain_services).to contain_exactly(
        'glance-api', 'nova-api', 'nova-metadata', 'placement',
        'neutron-server', 'cinder-api', 'heat-api', 'heat-cfn',
        'horizon-http'
      )
    end

    it 'tags horizon-http as a redirect-only listener' do
      horizon_http = services.find { |s| s[:name] == 'horizon-http' }
      expect(horizon_http[:redirect_to_https]).to be true
    end

    it 'does not tag any tls listener as redirect_to_https' do
      tls_redirects = services.select { |s| s[:tls] && s[:redirect_to_https] }
      expect(tls_redirects).to be_empty
    end
  end
end
