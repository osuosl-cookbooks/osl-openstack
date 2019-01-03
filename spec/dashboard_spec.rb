require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::dashboard', dashboard: true do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      node.automatic['filesystem2']['by_mountpoint']
    end
  end
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'identity_stubs'
  include_context 'dashboard_stubs'
  %w(
    osl-openstack
    memcached
    openstack-dashboard::horizon
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  [
    %r{SSLCertificateFile /etc/pki/tls/certs/wildcard.pem},
    %r{SSLCertificateKeyFile /etc/pki/tls/private/wildcard.key},
    %r{SSLCertificateChainFile /etc/pki/tls/certs/wildcard-bundle.crt},
  ].each do |line|
    it do
      expect(chef_run).to render_file('/etc/httpd/sites-available/openstack-dashboard.conf').with_content(line)
    end
  end
end
