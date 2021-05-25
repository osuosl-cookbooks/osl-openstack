require_relative 'spec_helper'

describe 'osl-openstack::identity', identity: true do
  let(:runner) { ChefSpec::SoloRunner.new(REDHAT_OPTS) }
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  %w(
    osl-openstack
    osl-openstack::ops_messaging
    openstack-identity::server-apache
    openstack-identity::registration
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end

  it { expect(chef_run).to accept_osl_firewall_openstack('osl-openstack') }

  describe '/etc/keystone/keystone.conf' do
    let(:file) { chef_run.template('/etc/keystone/keystone.conf') }
    [
      %r{^public_endpoint = https://10.0.0.10:5000/$},
      %r{^transport_url = rabbit://openstack:openstack@10.0.0.10:5672$},
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('DEFAULT', line)
      end
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
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content(
          'database',
          %r{^connection = mysql\+pymysql://keystone_x86:keystone_db_pass@10.0.0.10:3306/keystone_x86\?charset=utf8$}
        )
    end
    it do
      expect(chef_run).to_not render_config_file(file.name)
        .with_section_content('catalog', 'keystone.catalog.backends.sql.Catalog')
    end
    it do
      expect(chef_run).to_not render_config_file(file.name)
        .with_section_content('policy', 'driver = keystone.policy.backends.sql.Policy')
    end
    it do
      expect(chef_run).to_not render_config_file(file.name)
        .with_section_content('assignment', 'driver = keystone.assignment.backends.sql.Assignment')
    end
  end
  describe '/etc/keystone/keystone-paste.ini' do
    let(:file) do
      chef_run.template('/etc/keystone/keystone-paste.ini')
    end
    [
      /^use = egg:oslo.middleware\#cors$/,
      /^oslo_config_project = keystone$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('filter:cors', line)
      end
    end
    it do
      expect(chef_run).to_not render_config_file(file.name)
        .with_section_content('filter:osprofiler', 'use = egg:osprofiler\#osprofiler')
    end
    it do
      expect(chef_run).to_not render_config_file(file.name)
        .with_section_content('filter:http_proxy_to_wsgi', 'use = egg:oslo.middleware\#http_proxy_to_wsgi')
    end
    it do
      expect(chef_run).to render_config_file(file.name)
        .with_section_content('pipeline:api_v3', 'pipeline = cors sizelimit http_proxy_to_wsgi osprofiler url_normalize request_id build_auth_context token_auth json_body ec2_extension_v3 s3_extension service_v3')
    end
  end
  describe '/etc/httpd/sites-available/identity.conf' do
    let(:file) do
      chef_run.template('/etc/httpd/sites-available/identity.conf')
    end
    [
      /^<VirtualHost 0.0.0.0:5000>$/,
      %r{SSLCertificateFile /etc/pki/tls/certs/wildcard.pem$},
      %r{SSLCertificateKeyFile /etc/pki/tls/private/wildcard.key$},
      %r{SSLCertificateChainFile /etc/pki/tls/certs/wildcard-bundle.crt$},
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_content(line)
      end
    end
  end
end
