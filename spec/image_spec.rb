require_relative 'spec_helper'

describe 'osl-openstack::image' do
  cached(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      # Work around for base::ifconfig:47
      node.automatic['virtualization']['system']
    end
  end
  cached(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'identity_stubs'
  include_context 'image_stubs'
  %w(
    osl-openstack
    firewall::openstack
    openstack-image::api
    openstack-image::registry
    openstack-image::identity_registration
    openstack-image::image_upload
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
end
