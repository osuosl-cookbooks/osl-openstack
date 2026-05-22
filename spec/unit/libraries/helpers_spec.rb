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
end
