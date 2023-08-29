require_relative 'spec_helper'
require 'chef/application'

describe 'osl-openstack::block_storage_controller' do
  let(:runner) { ChefSpec::SoloRunner.new(REDHAT_OPTS) }
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  include_context 'block_storage_stubs'
  %w(
    osl-openstack
    openstack-block-storage::api
    openstack-block-storage::scheduler
    openstack-block-storage::identity_registration
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end

  it { expect(chef_run).to accept_osl_firewall_openstack('osl-openstack') }

  describe '/etc/cinder/cinder.conf' do
    let(:file) { chef_run.template('/etc/cinder/cinder.conf') }
    [
      /^my_ip = 10.0.0.2$/,
      %r{^glance_api_servers = http://10.0.0.10:9292},
      /^osapi_volume_listen = 10.0.0.2$/,
      /^volume_group = openstack$/,
      /^volume_clear_size = 256$/,
      /^enable_v3_api = true$/,
      %r{^transport_url = rabbit://openstack:mq-pass@10.0.0.10:5672$},
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('DEFAULT', line)
      end
    end
    it do
      expect(chef_run).to_not render_config_file(file.name).with_section_content('DEFAULT', /glance_api_version/)
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'oslo_messaging_notifications',
          /^driver = messagingv2$/
        )
    end
    [
      %r{^www_authenticate_uri = https://10.0.0.10:5000/v3$},
      /^service_token_roles_required = True$/,
      /^service_token_roles = admin$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('keystone_authtoken', line)
      end
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'database',
          %r{^connection = mysql\+pymysql://cinder_x86:cinder@10.0.0.10:3306/cinder_x86\?charset=utf8}
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
        expect(chef_run).to render_config_file(file.name).with_section_content('cache', line)
      end
    end
    it do
      expect(chef_run).to edit_replace_or_add('log-dir controller')
        .with(
          path: '/usr/share/cinder/cinder-dist.conf',
          pattern: '^logdir.*',
          replace_only: true,
          backup: true
        )
    end
    %w(service[apache2] service[cinder-scheduler]).each do |service|
      it do
        expect(chef_run.replace_or_add('log-dir controller')).to notify(service).to(:restart)
      end
    end
    context 'Set ceph' do
      let(:runner) do
        ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
          node.override['osl-openstack']['ceph']['volume'] = true
          node.automatic['filesystem2']['by_mountpoint']
        end
      end
      let(:node) { runner.node }
      cached(:chef_run) { runner.converge(described_recipe) }
      include_context 'common_stubs'
      [
        /^enabled_backends = ceph,ceph_ssd$/,
        /^backup_driver = cinder.backup.drivers.ceph$/,
        %r{^backup_ceph_conf = /etc/ceph/ceph.conf$},
        /^backup_ceph_user = cinder-backup$/,
        /^backup_ceph_chunk_size = 134217728$/,
        /^backup_ceph_pool = backups$/,
        /^backup_ceph_stripe_unit = 0$/,
        /^backup_ceph_stripe_count = 0$/,
        /^restore_discard_excess_bytes = true$/,
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name).with_section_content('DEFAULT', line)
        end
      end
      [
        /^volume_driver = cinder.volume.drivers.rbd.RBDDriver$/,
        /^volume_backend_name = ceph$/,
        /^rbd_pool = volumes$/,
        %r{rbd_ceph_conf = /etc/ceph/ceph.conf$},
        /^rbd_flatten_volume_from_snapshot = false$/,
        /^rbd_max_clone_depth = 5$/,
        /^rbd_store_chunk_size = 4$/,
        /^rados_connect_timeout = -1$/,
        /^rbd_user = cinder$/,
        /^rbd_secret_uuid = 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8$/,
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name).with_section_content('ceph', line)
        end
      end
      [
        /^volume_driver = cinder.volume.drivers.rbd.RBDDriver$/,
        /^volume_backend_name = ceph_ssd$/,
        /^rbd_pool = volumes_ssd$/,
        %r{rbd_ceph_conf = /etc/ceph/ceph.conf$},
        /^rbd_flatten_volume_from_snapshot = false$/,
        /^rbd_max_clone_depth = 5$/,
        /^rbd_store_chunk_size = 4$/,
        /^rados_connect_timeout = -1$/,
        /^rbd_user = cinder$/,
        /^rbd_secret_uuid = 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8$/,
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name).with_section_content('ceph_ssd', line)
        end
      end
      [
        /^rbd_user = cinder$/,
        /^rbd_secret_uuid = 8102bb29-f48b-4f6e-81d7-4c59d80ec6b8$/,
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name).with_section_content('libvirt', line)
        end
      end
    end
  end
end
