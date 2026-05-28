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
