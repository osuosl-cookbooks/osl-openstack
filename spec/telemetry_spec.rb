require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::telemetry', telemetry: true do
  let(:runner) { ChefSpec::SoloRunner.new(REDHAT_OPTS) }
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  include_context 'telemetry_stubs'
  %w(
    osl-openstack
    openstack-telemetry::gnocchi_install
    openstack-telemetry::gnocchi_configure
    openstack-telemetry::api
    openstack-telemetry::agent-central
    openstack-telemetry::agent-notification
    openstack-telemetry::collector
    openstack-telemetry::identity_registration
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  it do
    expect(chef_run).to run_execute('run gnocchi-upgrade').with(group: 'ceph')
  end
  it do
    expect(chef_run).to start_service('gnocchi-metricd').with(service_name: 'httpd')
  end
  it do
    expect(chef_run).to create_cookbook_file('/etc/gnocchi/api-paste.ini')
      .with(
        source: 'gnocchi/api-paste.ini',
        cookbook: 'osl-openstack'
      )
  end
  it do
    expect(chef_run).to modify_group('ceph-telemetry')
      .with(
        group_name: 'ceph',
        append: true,
        members: %w(gnocchi)
      )
  end
  it do
    expect(chef_run.group('ceph-telemetry')).to notify('service[gnocchi-metricd]').immediately
  end
  it do
    expect(chef_run).to create_file('/usr/share/gnocchi/gnocchi-dist.conf').with(mode: '0644')
  end
  describe '/etc/ceilometer/ceilometer.conf' do
    let(:file) { chef_run.template('/etc/ceilometer/ceilometer.conf') }
    [
      %r{^transport_url = rabbit://openstack:mq-pass@10.0.0.10:5672$},
      /^meter_dispatchers = gnocchi$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('DEFAULT', line)
      end
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'oslo_messaging_notifications',
          /^driver = messagingv2$/
        )
    end
    [
      %r{^auth_url = https://10.0.0.10:5000/v3$},
      %r{^auth_uri = https://10.0.0.10:5000/v3$},
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('keystone_authtoken', line)
      end
    end
    [
      /^host = 10.0.0.2$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('api', line)
      end
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'dispatcher_gnocchi',
          %r{^url = http://10.0.0.10:8041$}
        )
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'database',
          %r{^connection = mysql\+pymysql://ceilometer_x86:ceilometer-dbpass@10.0.0.10:3306/\
ceilometer_x86\?charset=utf8}
        )
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'keystone_authtoken',
          /^memcached_servers = 10.0.0.10:11211$/
        )
    end

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
  describe '/etc/gnocchi/gnocchi.conf' do
    let(:file) { chef_run.template('/etc/gnocchi/gnocchi.conf') }
    [
      %r{^auth_url = https://10.0.0.10:5000/v3$},
      /^password = gnocchi-pass$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('keystone_authtoken', line)
      end
    end
    [
      /^driver = ceph$/,
      /^ceph_pool = metrics$/,
      /^ceph_username = gnocchi$/,
      %r{^ceph_keyring = /etc/ceph/ceph.client.gnocchi.keyring$},
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('storage', line)
      end
    end
    it do
      expect(chef_run).to_not render_config_file(file.name)
        .with_section_content(
          'storage',
          %r{^file_basepath = /var/lib/gnocchi$}
        )
    end
    [
      /^auth_mode = keystone$/,
      /^host = 10.0.0.2$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('api', line)
      end
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'database',
          %r{^connection = mysql\+pymysql://gnocchi_x86:gnocchi-dbpass@10.0.0.10:3306/gnocchi_x86\?charset=utf8$}
        )
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'indexer',
          %r{^url = mysql\+pymysql://gnocchi_x86:gnocchi-dbpass@10.0.0.10:3306/gnocchi_x86\?charset=utf8$}
        )
    end
  end
end
