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
    openstack-telemetry::agent-central
    openstack-telemetry::agent-notification
    openstack-telemetry::identity_registration
  ).each do |r|
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  it do
    expect(chef_run).to install_package('patch')
  end
  it do
    expect(chef_run).to create_cookbook_file('/var/chef/cache/ceilometer-prometheus1.patch')
  end
  it do
    expect(chef_run).to create_cookbook_file('/var/chef/cache/ceilometer-prometheus2.patch')
  end
  it do
    expect(chef_run).to run_execute('patch -p1 < /var/chef/cache/ceilometer-prometheus1.patch')
      .with(cwd: '/usr/lib/python2.7/site-packages')
  end
  it do
    expect(chef_run).to run_execute('patch -p1 < /var/chef/cache/ceilometer-prometheus2.patch')
      .with(cwd: '/usr/lib/python2.7/site-packages')
  end
  it do
    expect(chef_run.execute('patch -p1 < /var/chef/cache/ceilometer-prometheus1.patch')) \
      .to notify('service[ceilometer-agent-central]').to(:restart)
  end
  it do
    expect(chef_run.execute('patch -p1 < /var/chef/cache/ceilometer-prometheus1.patch')) \
      .to notify('service[ceilometer-agent-notification]').to(:restart)
  end
  it do
    expect(chef_run.execute('patch -p1 < /var/chef/cache/ceilometer-prometheus1.patch')) \
      .to notify('service[apache2]').to(:restart)
  end
  it do
    expect(chef_run.execute('patch -p1 < /var/chef/cache/ceilometer-prometheus2.patch')) \
      .to notify('service[ceilometer-agent-central]').to(:restart)
  end
  it do
    expect(chef_run.execute('patch -p1 < /var/chef/cache/ceilometer-prometheus2.patch')) \
      .to notify('service[ceilometer-agent-notification]').to(:restart)
  end
  it do
    expect(chef_run.execute('patch -p1 < /var/chef/cache/ceilometer-prometheus2.patch')) \
      .to notify('service[apache2]').to(:restart)
  end
  context 'ceilometer patched' do
    cached(:chef_run) { runner.converge(described_recipe) }
    before do
      stub_command('grep -q curated_sname /usr/lib/python2.7/site-packages/ceilometer/publisher/prometheus.py')
        .and_return(true)
      stub_command('grep -q s.project_id /usr/lib/python2.7/site-packages/ceilometer/publisher/prometheus.py')
        .and_return(true)
    end
    it do
      expect(chef_run).to_not run_execute('patch -p1 < /var/chef/cache/ceilometer-prometheus1.patch')
        .with(
          cwd: '/usr/lib/python2.7/site-packages'
        )
    end
    it do
      expect(chef_run).to_not run_execute('patch -p1 < /var/chef/cache/ceilometer-prometheus2.patch')
        .with(
          cwd: '/usr/lib/python2.7/site-packages'
        )
    end
  end
  describe '/etc/ceilometer/ceilometer.conf' do
    let(:file) { chef_run.template('/etc/ceilometer/ceilometer.conf') }
    [
      %r{^transport_url = rabbit://openstack:mq-pass@10.0.0.10:5672$},
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('DEFAULT', line)
      end
    end
    [
      /^meter_dispatchers = gnocchi$/,
    ].each do |line|
      it do
        expect(chef_run).to_not render_config_file(file.name).with_section_content('DEFAULT', line)
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
      %r{^auth_url = https://10.0.0.10:5000/v3$},
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
          %r{^connection = mysql\+pymysql://ceilometer_x86:ceilometer-dbpass@10.0.0.10:3306/\
ceilometer_x86\?charset=utf8}
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
        expect(chef_run).to render_config_file(file.name)
          .with_section_content('cache', line)
      end
    end
    it do
      expect(chef_run).to stop_service('gnocchi-metricd').with(service_name: 'gnocchi-metricd')
    end
    it do
      expect(chef_run).to disable_service('gnocchi-metricd').with(service_name: 'gnocchi-metricd')
    end
    it do
      expect(chef_run).to delete_file('/etc/httpd/sites-enabled/gnocchi-api.conf').with(manage_symlink_source: true)
    end
    it do
      expect(chef_run).to delete_file('/etc/httpd/sites-available/gnocchi-api.conf').with(manage_symlink_source: true)
    end
    it do
      expect(chef_run.file('/etc/httpd/sites-enabled/gnocchi-api.conf')).to notify('service[apache2]').to(:restart)
    end
    it do
      expect(chef_run.file('/etc/httpd/sites-available/gnocchi-api.conf')).to notify('service[apache2]').to(:restart)
    end
    it do
      expect(chef_run).to remove_package(%w(openstack-gnocchi-api openstack-gnocchi-metricd gnocchi-common python-gnocchi))
    end
  end
end
