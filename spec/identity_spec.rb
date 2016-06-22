require_relative 'spec_helper'

describe 'osl-openstack::identity', identity: true do
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
  %w(
    osl-openstack
    osl-openstack::ops_messaging
    firewall::openstack
    openstack-identity::server-apache
    openstack-identity::registration
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  describe '/etc/keystone/keystone.conf' do
    let(:file) { chef_run.template('/etc/keystone/keystone.conf') }
    [
      %r{^public_endpoint = http://10.0.0.10:5000/$},
      %r{^admin_endpoint = http://10.0.0.10:35357/$}
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('DEFAULT', line)
      end
    end

    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'memcache',
          /^servers = 10.0.0.10:11211$/
        )
    end

    [
      /^rabbit_host = 10.0.0.10$/,
      /^rabbit_userid = guest$/,
      /^rabbit_password = guest$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('oslo_messaging_rabbit', line)
      end
    end

    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'database',
          %r{^connection = mysql://keystone_x86:keystone_db_pass@10.0.0.10:\
3306/keystone_x86\?charset=utf8$}
        )
    end
  end
  describe '/etc/httpd/sites-available/keystone-admin.conf' do
    let(:file) do
      chef_run.template('/etc/httpd/sites-available/keystone-admin.conf')
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_content(/^<VirtualHost 0.0.0.0:35357>$/)
    end
  end
  describe '/etc/httpd/sites-available/keystone-main.conf' do
    let(:file) do
      chef_run.template('/etc/httpd/sites-available/keystone-main.conf')
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_content(/^<VirtualHost 0.0.0.0:5000>$/)
    end
  end
end
