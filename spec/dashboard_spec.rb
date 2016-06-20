require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::dashboard', dashboard: true do
  secret_lock_file =
    ::File.join('/', 'usr', 'share', 'openstack-dashboard',
                'openstack_dashboard', 'local',
                '_usr_share_openstack-dashboard_openstack_dashboard_local' \
                '_.secret_key_store.lock')
  secret_file =
    ::File.join('/', 'usr', 'share', 'openstack-dashboard',
                'openstack_dashboard', 'local', '.secret_key_store')
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      # Work around for base::ifconfig:47
      node.automatic['virtualization']['system']
    end
  end
  let(:node) { runner.node }
  let(:secret_lock_file_resource) { chef_run.file(secret_lock_file) }
  let(:secret_file_resource) { chef_run.file(secret_file) }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'identity_stubs'
  include_context 'dashboard_stubs'
  %w(
    osl-openstack
    memcached
    openstack-dashboard::server
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  context 'Secret files already exist' do
    let(:chef_run) { runner.converge(described_recipe) }
    it 'Set secret key lock file permissions' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(secret_lock_file).and_return(true)
      expect(chef_run).to create_file(secret_lock_file).with(
        user: 'root',
        group: 'apache',
        mode: 0660
      )
    end
    it 'Set secret key file permissions' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(secret_file).and_return(true)
      expect(chef_run).to create_file(secret_file).with(
        user: 'apache',
        group: 'apache',
        mode: 0600
      )
    end
  end
  context 'Secret files do not exist' do
    cached(:chef_run) { runner.converge(described_recipe) }
    it 'Does not set secret key lock file permissions' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(secret_lock_file).and_return(false)
      expect(chef_run).to_not create_file(secret_lock_file).with(
        user: 'root',
        group: 'apache',
        mode: 0660
      )
    end
    it 'Does not set secret key file permissions' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(secret_file).and_return(false)
      expect(chef_run).to_not create_file(secret_file).with(
        user: 'apache',
        group: 'apache',
        mode: 0600
      )
    end
  end
  it 'Secret lock file subscribes to apache service immediately' do
    expect(secret_lock_file_resource).to subscribe_to('service[apache2]')
      .immediately
  end
  it 'Secret file subscribes to apache service immediately' do
    expect(secret_file_resource).to subscribe_to('service[apache2]').immediately
  end
end
