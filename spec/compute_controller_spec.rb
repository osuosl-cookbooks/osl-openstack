require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::compute_controller' do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      # Work around for base::ifconfig:47
      node.automatic['virtualization']['system']
    end
  end
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'identity_stubs'
  include_context 'compute_stubs'
  %w(
    osl-openstack
    firewall::openstack
    openstack-compute::nova-setup
    openstack-compute::conductor
    openstack-compute::scheduler
    openstack-compute::api-os-compute
    openstack-compute::api-metadata
    openstack-compute::nova-cert
    openstack-compute::vncproxy
    openstack-compute::identity_registration
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end

  it 'creates /etc/nova/pki directory' do
    expect(chef_run).to create_directory('/etc/nova/pki')
  end

  it 'creates novnc certificate resource' do
    expect(chef_run).to create_certificate_manage('novnc')
  end

  it 'creates novncproxy sysconfig template' do
    expect(chef_run).to \
      create_template('/etc/sysconfig/openstack-nova-novncproxy')
  end

  it 'novnc-proxy sysconfig file notifies openstack-nova-novncproxy service' do
    expect(chef_run.template('/etc/sysconfig/openstack-nova-novncproxy')).to \
      notify('service[openstack-nova-novncproxy]')
  end
end
