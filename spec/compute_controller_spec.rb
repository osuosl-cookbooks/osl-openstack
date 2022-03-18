require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::compute_controller' do
  let(:runner) { ChefSpec::SoloRunner.new(REDHAT_OPTS) }
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  include_context 'compute_stubs'
  %w(
    osl-openstack
    openstack-compute::nova-setup
    openstack-compute::identity_registration
    openstack-compute::conductor
    openstack-compute::scheduler
    openstack-compute::api-os-compute
    openstack-compute::api-metadata
    openstack-compute::placement_api
    openstack-compute::vncproxy
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end

  it { expect(chef_run).to accept_osl_firewall_openstack('osl-openstack') }

  it do
    expect(chef_run).to edit_delete_lines('remove dhcpbridge on controller')
      .with(
        path: '/usr/share/nova/nova-dist.conf',
        pattern: '^dhcpbridge.*',
        backup: true
      )
  end

  it do
    expect(chef_run).to edit_delete_lines('remove force_dhcp_release on controller')
      .with(
        path: '/usr/share/nova/nova-dist.conf',
        pattern: '^force_dhcp_release.*',
        backup: true
      )
  end

  %w(
    service[apache2]
    service[openstack-nova-novncproxy]
    service[nova-scheduler]
  ).each do |service|
    it do
      expect(chef_run.delete_lines('remove dhcpbridge on controller')).to notify(service).to(:restart)
    end

    it do
      expect(chef_run.delete_lines('remove force_dhcp_release on controller')).to notify(service).to(:restart)
    end
  end

  describe '/etc/nova/nova.conf' do
    let(:file) { chef_run.template('/etc/nova/nova.conf') }

    [
      /^disk_allocation_ratio = 1.5$/,
      /^instance_usage_audit = True$/,
      /^instance_usage_audit_period = hour$/,
      /^metadata_listen = 10.0.0.2$/,
      /^resume_guests_state_on_host_boot = True$/,
      /^block_device_allocate_retries = 120$/,
      %r{^transport_url = rabbit://openstack:mq-pass@10.0.0.10:5672$},
      /^compute_monitors = cpu.virt_driver$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('DEFAULT', line)
      end
    end
    it do
      expect(chef_run).to_not render_config_file(file.name)
        .with_section_content(
          'DEFAULT',
          /^use_neutron =/
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
          'filter_scheduler',
          /^enabled_filters = AggregateInstanceExtraSpecsFilter,PciPassthroughFilter,AvailabilityZoneFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter$/
        )
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'notifications',
          /^notify_on_state_change = vm_and_task_state$/
        )
    end
    [
      /^backend = oslo_cache.memcache_pool$/,
      /^enabled = true$/,
      /^memcache_servers = 10.0.0.10:11211$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('cache', line)
      end
    end

    [
      /^memcached_servers = 10.0.0.10:11211$/,
      %r{^auth_url = https://10.0.0.10:5000/v3$},
      %r{^www_authenticate_uri = https://10.0.0.10:5000/v3$},
      /^service_token_roles_required = True$/,
      /^service_token_roles = admin$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('keystone_authtoken', line)
      end
    end

    [
      /^virt_type = kvm$/,
      /^disk_cachemodes = file=writeback,block=none$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('libvirt', line)
      end
    end

    [
      /^service_metadata_proxy = true$/,
      %r{^auth_url = https://10.0.0.10:5000/v3$},
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('neutron', line)
      end
    end

    [
      %r{^novncproxy_base_url = https://10.0.0.10:6080/vnc_auto.html$},
      /^novncproxy_host = 10.0.0.2$/,
      /^server_listen = 10.0.0.2$/,
      /^server_proxyclient_address = 10.0.0.2$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('vnc', line)
      end
    end

    [
      %r{^api_servers = http://10.0.0.10:9292$},
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('glance', line)
      end
    end

    [
      %r{^base_url = ws://10.0.0.10:6083$},
      /^proxyclient_address = 127.0.0.1$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('serial_console', line)
      end
    end

    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'database',
          %r{^connection = mysql\+pymysql://nova_x86:nova_db_pass@10.0.0.10:3306/nova_x86\?charset=utf8$}
        )
    end

    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'api_database',
          %r{^connection = mysql\+pymysql://nova_api_x86:nova_api_db_pass@10.0.0.10:3306/nova_api_x86\?charset=utf8$}
        )
    end
    context 'Set ceph' do
      let(:runner) do
        ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
          node.override['osl-openstack']['ceph']['compute'] = true
          node.override['osl-openstack']['ceph']['volume'] = true
          node.automatic['filesystem2']['by_mountpoint']
        end
      end
      let(:node) { runner.node }
      cached(:chef_run) { runner.converge(described_recipe) }
      include_context 'common_stubs'
      include_context 'ceph_stubs'
      migrate_flags =
        %w(
          VIR_MIGRATE_UNDEFINE_SOURCE
          VIR_MIGRATE_PEER2PEER
          VIR_MIGRATE_LIVE
          VIR_MIGRATE_PERSIST_DEST
          VIR_MIGRATE_TUNNELLED
        )
      [
        /^disk_cachemodes = network=writeback$/,
        /^force_raw_images = true$/,
        /^hw_disk_discard = unmap$/,
        %r{images_rbd_ceph_conf = /etc/ceph/ceph.conf$},
        /^images_rbd_pool = vms$/,
        /^images_type = rbd$/,
        /^inject_key = false$/,
        /^inject_partition = -2$/,
        /^inject_password = false$/,
        /^live_migration_flag = #{migrate_flags.join(',')}$/,
        /^rbd_secret_uuid = 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8$/,
        /^rbd_user = cinder$/,
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name).with_section_content('libvirt', line)
        end
      end
    end
  end

  it do
    expect(chef_run).to install_apache2_install('openstack').with(
      listen: %w(10.0.0.2:8774 10.0.0.2:8775 10.0.0.2:8778)
    )
  end

  describe '/etc/httpd/sites-available/nova-metadata.conf' do
    let(:file) { chef_run.template('/etc/httpd/sites-available/nova-metadata.conf') }

    [
      /^<VirtualHost 10.0.0.2:8775>$/,
      /WSGIDaemonProcess nova-metadata processes=6 threads=1/,
    ].each do |line|
      it do
        expect(chef_run).to render_file(file.name).with_content(line)
      end
    end
  end

  describe '/etc/httpd/sites-available/placement.conf' do
    let(:file) { chef_run.template('/etc/httpd/sites-available/placement.conf') }

    [
      /^<VirtualHost 10.0.0.2:8778>$/,
      /WSGIDaemonProcess placement-api processes=2 threads=1/,
    ].each do |line|
      it do
        expect(chef_run).to render_file(file.name).with_content(line)
      end
    end
  end

  it 'creates novnc certificate resource' do
    expect(chef_run).to create_certificate_manage('novnc')
  end

  it 'creates novncproxy sysconfig template' do
    expect(chef_run).to create_template('/etc/sysconfig/openstack-nova-novncproxy')
  end

  it 'novnc-proxy sysconfig file notifies openstack-nova-novncproxy service' do
    expect(chef_run.template('/etc/sysconfig/openstack-nova-novncproxy')).to \
      notify('service[openstack-nova-novncproxy]')
  end
end
