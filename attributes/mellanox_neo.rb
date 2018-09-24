default['osl-openstack']['mellanox_neo']['server_hostname'] = node['fqdn']
default['osl-openstack']['mellanox_neo']['packages'] = %w(
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
)
default['osl-openstack']['mellanox_neo']['services'] = {
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
}
default['osl-openstack']['mellanox_neo']['port_check_bin'] =
  '/opt/neo/common/bin/netservices/common/utils/ports_validator.pyo'
