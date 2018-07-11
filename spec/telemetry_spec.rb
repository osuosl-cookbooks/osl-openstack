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
  describe '/etc/ceilometer/ceilometer.conf' do
    let(:file) { chef_run.template('/etc/ceilometer/ceilometer.conf') }
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'DEFAULT',
          %r{^transport_url = rabbit://guest:mq-pass@10.0.0.10:5672$}
        )
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'oslo_messaging_notifications',
          /^driver = messagingv2$/
        )
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'keystone_authtoken',
          %r{^auth_url = https://10.0.0.10:5000/v3$}
        )
    end
    [
      /^host = 10.0.0.2$/,
      /^default_api_return_limit = 1000000000000$/
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
          %r{^connection = mysql://ceilometer_x86:ceilometer-dbpass@10.0.0.10:\
3306/ceilometer_x86\?charset=utf8}
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
      /^memcache_servers = 10.0.0.10:11211$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('cache', line)
      end
    end

    [
      /^rabbit_host = 10.0.0.10$/,
      /^rabbit_userid = guest$/,
      /^rabbit_password = mq-pass$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('oslo_messaging_rabbit', line)
      end
    end
  end
end
