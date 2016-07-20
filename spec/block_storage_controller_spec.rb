require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::block_storage_controller',
         block_storage_controller: true do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      # Work around for base::ifconfig:47
      node.automatic['virtualization']['system']
    end
  end
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  include_context 'block_storage_stubs'
  %w(
    osl-openstack
    firewall::openstack
    openstack-block-storage::api
    openstack-block-storage::scheduler
    openstack-block-storage::identity_registration
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  describe '/etc/cinder/cinder.conf' do
    let(:file) { chef_run.template('/etc/cinder/cinder.conf') }
    [
      /^glance_host = 10.0.0.10$/,
      /^my_ip = 10.0.0.2$/,
      %r{^glance_api_servers = http://10.0.0.10:9292},
      /^osapi_volume_listen = 10.0.0.2$/,
      /^volume_group = openstack$/,
      /^volume_clear_size = 256$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('DEFAULT', line)
      end
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
          %r{^auth_url = http://10.0.0.10:5000/v2.0$}
        )
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'database',
          %r{^connection = mysql://cinder_x86:cinder@10.0.0.10:3306/\
cinder_x86\?charset=utf8}
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
