require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::controller' do
  let(:runner) { ChefSpec::SoloRunner.new(REDHAT_OPTS) }
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  %w(
    common_stubs
    identity_stubs
    image_stubs
    network_stubs
    compute_stubs
    block_storage_stubs
    dashboard_stubs
    telemetry_stubs
    orchestration_stubs
  ).each do |s|
    include_context s
  end
  %w(
    osl-apache::default
    osl-openstack::default
    memcached
    osl-openstack::identity
    osl-openstack::image
    osl-openstack::network
    osl-openstack::compute_controller
    osl-openstack::block_storage_controller
    osl-openstack::telemetry
    osl-openstack::dashboard
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end

  it { expect(chef_run).to accept_osl_firewall_openstack('osl-openstack') }
  it { expect(chef_run).to accept_osl_firewall_vnc('osl-openstack') }

  it 'adds cluster nodes ipaddresses' do
    expect(chef_run).to accept_osl_firewall_memcached('osl-openstack').with(
      allowed_ipv4: %w(10.0.0.10 10.0.0.11 127.0.0.1)
    )
  end

  describe '/etc/nova/nova.conf' do
    let(:file) { chef_run.template('/etc/nova/nova.conf') }

    [
      /^backend = oslo_cache.memcache_pool$/,
      /^enabled = true$/,
      /^memcache_servers = 10.0.0.10:11211$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('cache', line)
      end
    end
  end
  it do
    expect(chef_run).to install_apache2_install('openstack').with(
      modules: %w(status alias auth_basic authn_core authn_file authz_core authz_groupfile authz_host authz_user autoindex deflate dir env mime negotiation setenvif log_config logio unixd systemd),
      mpm_conf: {
        maxrequestworkers: 10,
        serverlimit: 10,
      },
      mod_conf: {
        status: {
          extended_status: 'On',
        },
      }
    )
  end
  context 'Separate Network Node' do
    cached(:chef_run) { runner.converge(described_recipe) }
    before do
      node.default['osl-openstack']['separate_network_node'] = true
    end
    it do
      expect(chef_run).to_not include_recipe('osl-openstack::network')
    end
  end
end
