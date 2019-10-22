require_relative '../../spec_helper'

describe 'osl-openstack::orchestration' do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS)
  end
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  include_context 'orchestration_stubs'
  it 'converges successfully' do
    expect { chef_run }.to_not raise_error
  end
  describe '/etc/heat/heat.conf' do
    let(:file) { chef_run.template('/etc/heat/heat.conf') }

    [
      %r{^heat_metadata_server_url = http://10.0.0.10:8000$},
      %r{^heat_waitcondition_server_url = http://10.0.0.10:8000/v1/waitcondition$},
      %r{^transport_url = rabbit://openstack:openstack@10.0.0.10:5672$},
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('DEFAULT', line)
      end
    end
    it do
      expect(chef_run).to render_config_file(file.name).with_section_content('trustee', /^auth_type = v3password$/)
    end
    it do
      expect(chef_run).to_not render_config_file(file.name).with_section_content('trustee', /^auth_plugin =/)
    end
    %w(heat_api heat_api_cfn).each do |service|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content(
            service,
            /^bind_host = 10.0.0.2$/
          )
      end
    end

    context 'Set bind_service' do
      let(:runner) do
        ChefSpec::SoloRunner.new(REDHAT_OPTS)
      end
      let(:node) { runner.node }
      cached(:chef_run) { runner.converge(described_recipe) }
      include_context 'common_stubs'
      %w(heat_api heat_api_cfn).each do |service|
        it do
          node.normal['osl-openstack']['bind_service'] = '192.168.1.1'
          expect(chef_run).to render_config_file(file.name)
            .with_section_content(
              service,
              /^bind_host = 192.168.1.1$/
            )
        end
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
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('keystone_authtoken', line)
      end
    end

    [
      %r{^connection = mysql\+pymysql://heat_x86:heat@10.0.0.10:3306/heat_x86\?charset=utf8$},
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('database', line)
      end
    end
  end
end
