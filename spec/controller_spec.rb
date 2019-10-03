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
    firewall::openstack
    firewall::memcached
    firewall::vnc
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
  it 'adds cluster nodes ipaddresses' do
    expect(chef_run).to create_iptables_ng_rule('memcached_ipv4').with(
      rule:
        [
          '--protocol tcp --source 10.0.0.10 --destination-port 11211 --jump ACCEPT',
          '--protocol udp --source 10.0.0.10 --destination-port 11211 --jump ACCEPT',
          '--protocol tcp --source 10.0.0.11 --destination-port 11211 --jump ACCEPT',
          '--protocol udp --source 10.0.0.11 --destination-port 11211 --jump ACCEPT',
          '--protocol tcp --source 127.0.0.1 --destination-port 11211 --jump ACCEPT',
          '--protocol udp --source 127.0.0.1 --destination-port 11211 --jump ACCEPT',
        ],
      chain: 'memcached'
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
  context 'Separate Network Node' do
    cached(:chef_run) { runner.converge(described_recipe) }
    before do
      node.normal['osl-openstack']['separate_network_node'] = true
    end
    it do
      expect(chef_run).to_not include_recipe('osl-openstack::network')
    end
  end
end
