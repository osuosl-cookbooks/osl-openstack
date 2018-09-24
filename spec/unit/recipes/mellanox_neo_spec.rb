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

  {
    'neo-access-credentials' => {
      'python_path' => %w(
        /opt/neo/providers/ac/bin
        /opt/neo/common/bin
        /opt/neo/providers/common/bin
      ),
      'port_check_config' => '/opt/neo/files/providers/ac/conf/netservice.cfg',
      'start_bin' => '/opt/neo/providers/ac/bin/ac/ac_service.pyo',
    },
    'neo-controller' => {
      'python_path' => %w(
        /opt/neo/controller/bin
        /opt/neo/common/bin
      ),
      'port_check_config' => '/opt/neo/files/controller/conf/controller.cfg --exclude-patterns Protocol::[\w]+',
      'start_bin' => '/opt/neo/controller/bin/controller/sdn_controller.pyo',
    },
    'neo-device-manager' => {
      'python_path' => %w(
        /opt/neo/providers/dm/bin
        /opt/neo/common/bin
        /opt/neo/providers/common/bin
      ),
      'port_check_config' => '/opt/neo/files/providers/dm/conf/netservice.cfg',
      'start_bin' => '/opt/neo/providers/dm/bin/dm/dm_service.pyo',
    },
    'neo-eth-discovery' => {
      'python_path' => %w(
        /opt/neo/providers/ethdisc/bin
        /opt/neo/common/bin
        /opt/neo/providers/common/bin
      ),
      'port_check_config' => '/opt/neo/files/providers/ethdisc/conf/netservice.cfg',
      'start_bin' => '/opt/neo/providers/ethdisc/bin/ethdisc/eth_discovery_service.pyo',
    },
    'neo-ib' => {
      'python_path' => %w(
        /opt/neo/providers/ib/bin
        /opt/neo/common/bin
        /opt/neo/providers/common/bin
      ),
      'port_check_config' => '/opt/neo/files/providers/ib/conf/netservice.cfg',
      'start_bin' => '/opt/neo/providers/ib/bin/ib/ib_service.pyo',
    },
    'neo-ip-discovery' => {
      'python_path' => %w(
        /opt/neo/providers/discovery/bin
        /opt/neo/common/bin
        /opt/neo/providers/common/bin
      ),
      'port_check_config' => '/opt/neo/files/providers/discovery/conf/netservice.cfg',
      'start_bin' => '/opt/neo/providers/discovery/bin/discovery/ip_discovery_service.pyo',
    },
    'neo-monitor' => {
      'python_path' => %w(
        /opt/neo/providers/monitor/bin
        /opt/neo/common/bin
        /opt/neo/providers/common/bin
      ),
      'port_check_config' => '/opt/neo/files/providers/monitor/conf/netservice.cfg',
      'start_bin' => '/opt/neo/providers/monitor/bin/monitor/monitor_service.pyo',
    },
    'neo-performance' => {
      'python_path' => %w(
        /opt/neo/providers/performance/bin
        /opt/neo/common/bin
        /opt/neo/providers/common/bin
        /opt/neo/tools/src
      ),
      'port_check_config' => '/opt/neo/files/providers/performance/conf/netservice.cfg',
      'start_bin' => '/opt/neo/providers/performance/bin/performance/perf_service.pyo',
    },
    'neo-provisioning' => {
      'python_path' => %w(
        /opt/neo/providers/provisioning/bin
        /opt/neo/common/bin
        /opt/neo/providers/common/bin
        /opt/neo/tools/src
      ),
      'port_check_config' => '/opt/neo/files/providers/provisioning/conf/netservice.cfg',
      'start_bin' => '/opt/neo/providers/provisioning/bin/provisioning/prov_service.pyo',
    },
    'neo-solution' => {
      'python_path' => %w(
        /opt/neo/providers/solution/bin
        /opt/neo/common/bin
        /opt/neo/providers/common/bin
      ),
      'port_check_config' => '/opt/neo/files/providers/solution/conf/netservice.cfg',
      'start_bin' => '/opt/neo/providers/solution/bin/solution/solution_service.pyo',
    },
    'neo-virtualization' => {
      'python_path' => %w(
        /opt/neo/providers/virtualization/bin
        /opt/neo/common/bin
        /opt/neo/providers/common/bin
      ),
      'port_check_config' => '/opt/neo/files/providers/virtualization/conf/netservice.cfg',
      'start_bin' => '/opt/neo/providers/virtualization/bin/virtualization/virtualization_service.pyo',
    },
  }.each do |service, options|
    it do
      port_check = '/opt/neo/common/bin/netservices/common/utils/ports_validator.pyo'
      expect(chef_run).to create_systemd_service(service)
        .with(
          description: service,
          after: %w(network.target),
          wanted_by: 'multi-user.target',
          environment: { 'PYTHONPATH' => options['python_path'].join(':') },
          exec_start_pre: "/usr/bin/python -O #{port_check} -f #{options['port_check_config']}",
          exec_start: '/bin/python -O ' + options['start_bin'],
          pid_file: "/var/run/#{service}.pid"
        )
    end
    it do
      expect(chef_run).to enable_service(service)
    end
    it do
      expect(chef_run).to start_service(service)
    end
  end

  it do
    expect(chef_run).to create_apache_app('fauxhai.local')
      .with(
        directory: '/opt/neo/controller/docs',
        directive_http: [
          'RewriteCond %{HTTPS} !=on',
          'RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R,L]',
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
