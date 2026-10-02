# Expected template variables for the test bag items; region2 is region2_secrets
CONTROLLER = 'controller.testing.osuosl.org'.freeze
CONTROLLER_REGION2 = 'controller_region2.testing.osuosl.org'.freeze

NOVA_ENABLED_FILTERS = %w(
  AggregateInstanceExtraSpecsFilter
  PciPassthroughFilter
  AvailabilityZoneFilter
  ComputeFilter
  ComputeCapabilitiesFilter
  ImagePropertiesFilter
  ServerGroupAntiAffinityFilter
  ServerGroupAffinityFilter
).freeze

def messaging_vars(host = CONTROLLER)
  {
    rabbit_quorum_queue: false,
    rabbit_tls: false,
    rabbit_ssl_ca_file: nil,
    transport_url: "rabbit://openstack:openstack@#{host}:5672/",
  }
end

def nova_conf_vars(region2: false)
  host = region2 ? CONTROLLER_REGION2 : CONTROLLER
  db = region2 ? 'localhost_region2' : 'localhost'
  gpu = '{ "vendor_id": "10de", "product_id": "1db5", "device_type": "type-PCI", "name": "gpu_nvidia_v100" }'
  {
    allow_resize_to_same_host: nil,
    api_database_connection: "mysql+pymysql://nova_x86:nova@#{db}:3306/nova_api_x86",
    auth_endpoint: CONTROLLER,
    cinder_disabled: region2,
    cpu_allocation_ratio: nil,
    database_connection: "mysql+pymysql://nova_x86:nova@#{db}:3306/nova_x86",
    disk_allocation_ratio: '1.5',
    enabled_filters: NOVA_ENABLED_FILTERS,
    endpoint: host,
    image_api_servers: "http://#{host}:9292",
    images_rbd_pool: region2 ? nil : 'vms',
    listen_ip: '*',
    local_storage: region2,
    memcached_endpoint: "#{host}:11211",
    metadata_proxy_shared_secret: '2SJh0RuO67KpZ63z',
    neutron_pass: 'neutron',
    pci_alias: region2 ? gpu : nil,
    pci_passthrough_whitelist: region2 ? '{ "vendor_id": "10de", "product_id": "1db5" }' : nil,
    placement_pass: 'placement',
    power10: false,
    ram_allocation_ratio: nil,
    rbd_secret_uuid: region2 ? nil : CEPH_FSID,
    rbd_user: region2 ? nil : 'cinder',
    region: region2 ? 'RegionTwo' : 'RegionOne',
    service_pass: 'nova',
    **messaging_vars(host),
  }
end

def neutron_conf_vars(controller:, region2: false)
  host = region2 ? CONTROLLER_REGION2 : CONTROLLER
  db = region2 ? 'localhost_region2' : 'localhost'
  {
    auth_endpoint: CONTROLLER,
    compute_pass: 'nova',
    controller: controller,
    ha: nil,
    listen_ip: '*',
    database_connection: "mysql+pymysql://neutron_x86:neutron@#{db}:3306/neutron_x86",
    memcached_endpoint: "#{host}:11211",
    neutron_venv: controller ? '/opt/openstack/neutron-controller' : '/opt/openstack/neutron-agent',
    region: region2 ? 'RegionTwo' : 'RegionOne',
    service_pass: 'neutron',
    **messaging_vars(host),
  }
end
