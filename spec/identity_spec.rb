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
  it do
    expect(chef_run.execute('Clear Keystone apache restart')).to do_nothing
  end
  %w(
    /etc/keystone/keystone.conf
    /etc/httpd/sites-available/keystone-admin.conf
    /etc/httpd/sites-available/keystone-main.conf
  ).each do |t|
    it do
      expect(chef_run.template(t)).to notify('execute[Clear Keystone apache restart]').to(:run).immediately
    end
  end
  describe '/etc/keystone/keystone.conf' do
    let(:file) { chef_run.template('/etc/keystone/keystone.conf') }
    [
      %r{^public_endpoint = https://10.0.0.10:5000/$},
      %r{^admin_endpoint = https://10.0.0.10:35357/$},
      %r{^transport_url = rabbit://guest:mq-pass@10.0.0.10:5672$}
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('DEFAULT', line)
      end
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
    [
      /^<VirtualHost 0.0.0.0:35357>$/,
      %r{SSLCertificateFile /etc/pki/tls/certs/wildcard.pem$},
      %r{SSLCertificateKeyFile /etc/pki/tls/private/wildcard.key$},
      %r{SSLCertificateChainFile /etc/pki/tls/certs/wildcard-bundle.crt$}
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_content(line)
      end
    end
  end
  describe '/etc/httpd/sites-available/keystone-main.conf' do
    let(:file) do
      chef_run.template('/etc/httpd/sites-available/keystone-main.conf')
    end
    [
      /^<VirtualHost 0.0.0.0:5000>$/,
      %r{SSLCertificateFile /etc/pki/tls/certs/wildcard.pem$},
      %r{SSLCertificateKeyFile /etc/pki/tls/private/wildcard.key$},
      %r{SSLCertificateChainFile /etc/pki/tls/certs/wildcard-bundle.crt$}
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_content(line)
      end
    end
  end
  it do
    expect(chef_run).to run_execute('Keystone apache restart')
      .with(
        command: "touch #{Chef::Config[:file_cache_path]}/keystone-apache-restarted",
        creates: "#{Chef::Config[:file_cache_path]}/keystone-apache-restarted"
      )
  end
end
