require_relative '../../spec_helper'

describe 'osl-openstack::mellanox_neo' do
  cached(:chef_run) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS).converge(described_recipe)
  end
  before do
    stub_command('/usr/sbin/httpd -t')
  end
  it 'converges successfully' do
    expect { chef_run }.to_not raise_error
  end

  it do
    expect(chef_run).to_not delete_directory('/etc/httpd/conf.d')
  end

  %w(
    osl-apache
    apache2::mod_ssl
    apache2::mod_proxy
    apache2::mod_proxy_http
    apache2::mod_proxy_balancer
    yum-epel
    certificate::wildcard
  ).each do |r|
    it do
      expect(chef_run).to include_recipe(r)
    end
  end

  it do
    expect(chef_run).to create_yum_repository('mellanox-neo')
      .with(
        description: 'Mellanox Neo',
        url: 'http://packages.osuosl.org/repositories/centos-$releasever/mellanox-neo',
        gpgcheck: false,
        priority: '1'
      )
  end

  %w(
    yum-plugin-priorities
    neo-controller
    neo-provider-ac
    neo-provider-common
    neo-provider-discovery
    neo-provider-dm
    neo-provider-ethdisc
    neo-provider-ib
    neo-provider-monitor
    neo-provider-performance
    neo-provider-provisioning
    neo-provider-solution
    neo-provider-virtualization
  ).each do |p|
    it do
      expect(chef_run).to install_package(p)
    end
  end

  %w(
    neo-access-credentials
    neo-controller
    neo-device-manager
    neo-eth-discovery
    neo-ib
    neo-ip-discovery
    neo-monitor
    neo-performance
    neo-provisioning
    neo-solution
    neo-virtualization
  ).each do |s|
    it do
      expect(chef_run).to enable_service(s)
    end
    it do
      expect(chef_run).to start_service(s)
    end
  end

  it do
    expect(chef_run).to create_apache_app('fauxhai.local')
      .with(
        directory: '/opt/neo/controller/docs',
        directive_http: [
          'RewriteCond %{HTTPS} !=on',
          'RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R,L]'
        ],
        ssl_enable: true,
        cert_chain: '/etc/pki/tls/certs/wildcard-bundle.crt',
        cert_file: '/etc/pki/tls/certs/wildcard.pem',
        cert_key: '/etc/pki/tls/private/wildcard.key',
        include_config: true,
        include_name: 'neo'
      )
  end
end
