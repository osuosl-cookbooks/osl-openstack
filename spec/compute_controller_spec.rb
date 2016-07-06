require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::compute_controller', compute_controller: true do
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

  describe '/etc/nova/nova.conf' do
    let(:file) { chef_run.template('/etc/nova/nova.conf') }

    [
      /^linuxnet_interface_driver = \
nova.network.linux_net.NeutronLinuxBridgeInterfaceDriver$/,
      /^dns_server = 140.211.166.130 140.211.166.131$/,
      /^instance_usage_audit = True$/,
      /^instance_usage_audit_period = hour$/,
      /^notify_on_state_change = vm_and_task_state$/,
      /^osapi_compute_listen = 10.0.0.2$/,
      /^metadata_listen = 10.0.0.2$/
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
      /^memcached_servers = 10.0.0.10:11211$/,
      %r{^auth_url = http://10.0.0.10:5000/v2.0$}
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('keystone_authtoken', line)
      end
    end

    [
      /^service_metadata_proxy = true$/,
      %r{^url = http://10.0.0.10:9696$},
      %r{^auth_url = http://10.0.0.10:5000/v2.0$}
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('neutron', line)
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

    [
      %r{^novncproxy_base_url = https://10.0.0.10:6080/vnc_auto.html$},
      %r{^xvpvncproxy_base_url = http://10.0.0.10:6081/console$},
      /^xvpvncproxy_host = 10.0.0.2$/,
      /^novncproxy_host = 10.0.0.2$/,
      /^vncserver_listen = 10.0.0.2$/,
      /^vncserver_proxyclient_address = 10.0.0.2$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('vnc', line)
      end
    end

    [
      %r{^api_servers = http://10.0.0.10:9292$}
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('glance', line)
      end
    end

    [
      %r{^base_url = ws://10.0.0.10:6083$},
      /^proxyclient_address = 127.0.0.1$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('serial_console', line)
      end
    end

    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'database',
          %r{^connection = mysql://nova_x86:nova_db_pass@10.0.0.10:3306/\
nova_x86\?charset=utf8$}
        )
    end

    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'api_database',
          %r{^connection = mysql://nova_api_x86:nova_api_db_pass@10.0.0.10:\
3306/nova_api_x86\?charset=utf8$}
        )
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
