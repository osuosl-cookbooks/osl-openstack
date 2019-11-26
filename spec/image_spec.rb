require_relative 'spec_helper'

describe 'osl-openstack::image', image: true do
  let(:runner) { ChefSpec::SoloRunner.new(REDHAT_OPTS) }
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  include_context 'image_stubs'
  %w(
    osl-openstack
    firewall::openstack
    openstack-image::api
    openstack-image::identity_registration
    openstack-image::image_upload
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  %w(api).each do |f|
    describe "/etc/glance/glance-#{f}.conf" do
      let(:file) { chef_run.template("/etc/glance/glance-#{f}.conf") }

      [
        /^bind_host = 10.0.0.2$/,
        %r{^transport_url = rabbit://openstack:mq-pass@10.0.0.10:5672$},
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name).with_section_content('DEFAULT', line)
        end
      end
      case f
      when 'api'
        [
          /^enable_v1_api = false$/,
          /^enable_v2_api = true$/,
        ].each do |line|
          it do
            expect(chef_run).to render_config_file(file.name).with_section_content('DEFAULT', line)
          end
        end
      end
      context 'Set ceph' do
        next unless f == 'api'
        let(:runner) do
          ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
            node.normal['osl-openstack']['ceph'] = true
            node.automatic['filesystem2']['by_mountpoint']
          end
        end
        let(:node) { runner.node }
        cached(:chef_run) { runner.converge(described_recipe) }
        include_context 'common_stubs'
        include_context 'ceph_stubs'
        it do
          expect(chef_run).to modify_group('ceph-image')
            .with(
              group_name: 'ceph',
              append: true,
              members: %w(glance)
            )
        end
        it do
          expect(chef_run.group('ceph-image')).to notify('service[glance-api]').to(:restart).immediately
        end
        it do
          expect(chef_run).to create_template('/etc/ceph/ceph.client.glance.keyring')
            .with(
              source: 'ceph.client.keyring.erb',
              owner: 'ceph',
              group: 'ceph',
              sensitive: true,
              variables: {
                ceph_user: 'glance',
                ceph_token: 'image_token',
              }
            )
        end
        it do
          expect(chef_run.template('/etc/ceph/ceph.client.glance.keyring')).to \
            notify('service[glance-api]').to(:restart)
        end
        [
          /^show_image_direct_url = true$/,
          /^show_multiple_locations = true$/,
          /^enabled_backends = cheap:rbd$/,
        ].each do |line|
          it do
            expect(chef_run).to render_config_file(file.name).with_section_content('DEFAULT', line)
          end
        end
        [
          /^flavor = keystone$/,
        ].each do |line|
          it do
            expect(chef_run).to render_config_file(file.name).with_section_content('paste_deploy', line)
          end
        end
        [
          /^default_backend = cheap$/,
        ].each do |line|
          it do
            expect(chef_run).to render_config_file(file.name).with_section_content('glance_store', line)
          end
        end
        [
          /^store_description = Cheap rbd backend$/,
          /^rbd_store_pool = images$/,
          /^rbd_store_user = glance$/,
          %r{^rbd_store_ceph_conf = /etc/ceph/ceph.conf$},
          /^rbd_store_chunk_size = 8$/,
        ].each do |line|
          it do
            expect(chef_run).to render_config_file(file.name).with_section_content('cheap', line)
          end
        end
        context 'no image_token' do
          next unless f == 'api'
          let(:runner) do
            ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
              node.normal['osl-openstack']['ceph'] = true
              node.automatic['filesystem2']['by_mountpoint']
            end
          end
          let(:node) { runner.node }
          cached(:chef_run) { runner.converge(described_recipe) }
          include_context 'common_stubs'
          include_context 'ceph_stubs'
          before do
            node.normal['osl-openstack']['credentials']['ceph']['image_token'] = nil
          end
          it do
            expect(chef_run).to_not create_template('/etc/ceph/ceph.client.glance.keyring')
          end
        end
      end

      context 'Set bind_service' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
            node.normal['osl-openstack']['bind_service'] = '192.168.1.1'
            node.automatic['filesystem2']['by_mountpoint']
          end.converge(described_recipe)
        end
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content(
              'DEFAULT',
              /^bind_host = 192.168.1.1$/
            )
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
        /^memcache_servers = 10.0.0.10:11211$/,
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content('cache', line)
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
          expect(chef_run).to render_config_file(file.name)
            .with_section_content('keystone_authtoken', line)
        end
      end

      [
        %r{^connection = mysql\+pymysql://glance_x86:db-pass@10.0.0.10:3306/glance_x86\?charset=utf8$},
      ].each do |line|
        it do
          expect(chef_run).to render_config_file(file.name)
            .with_section_content('database', line)
        end
      end
    end
  end
end
