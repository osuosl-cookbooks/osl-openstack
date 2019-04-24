#
# Cookbook:: osl-openstack
# Recipe:: default
#
# Copyright:: (C) 2014-2020 Oregon State University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Make Openstack object available in Chef::Recipe
class ::Chef::Recipe
  include ::Openstack
end

node.default['authorization']['sudo']['include_sudoers_d'] = true
node.default['apache']['contact'] = 'hostmaster@osuosl.org'
node.default['osl-apache']['server_status_port'] = 80
node.default['rabbitmq']['use_distro_version'] = true
node.default['openstack']['release'] = 'stein'
node.default['openstack']['is_release'] = true
node.default['openstack']['secret']['key_path'] =
  '/etc/chef/encrypted_data_bag_secret'
node.default['openstack']['misc_openrc'] = [
  'export OS_CACERT="/etc/ssl/certs/ca-bundle.crt"',
  'export OS_AUTH_TYPE=password',
]
node.default['openstack']['yum']['uri'] =
  case node['kernel']['machine']
  when 'ppc64le', 'aarch64'
    'http://centos-altarch.osuosl.org/$releasever/cloud/$basearch/openstack-' + node['openstack']['release']
  else
    'http://centos.osuosl.org/$releasever/cloud/$basearch/openstack-' + node['openstack']['release']
  end
node.default['openstack']['yum']['repo-key'] = 'https://www.centos.org/keys/RPM-GPG-KEY-CentOS-SIG-Cloud'
node.default['openstack']['identity']['ssl'].tap do |conf|
  conf['enabled'] = true
  conf['basedir'] = '/etc/pki/tls'
  conf['certfile'] = '/etc/pki/tls/certs/wildcard.pem'
  conf['keyfile'] = '/etc/pki/tls/private/wildcard.key'
  conf['chainfile'] = '/etc/pki/tls/certs/wildcard-bundle.crt'
  conf['ca_certs_path'] = '/etc/pki/tls/certs'
end

# Remove deprecated settings from upstream
node.default['openstack']['identity']['conf'].delete('policy')
node.default['openstack']['identity']['conf']['assignment']['driver'] = 'sql'
node.default['openstack']['identity']['misc_paste'] =
  [
    '[filter:cors]',
    'use = egg:oslo.middleware#cors',
    'oslo_config_project = keystone',
    '',
    '[filter:osprofiler]',
    'use = egg:osprofiler#osprofiler',
    '',
    '[filter:http_proxy_to_wsgi]',
    'use = egg:oslo.middleware#http_proxy_to_wsgi',
  ]
node.default['openstack']['identity']['pipeline']['api_v3'] =
  %w(
    cors
    sizelimit
    http_proxy_to_wsgi
    osprofiler
    url_normalize
    request_id
    build_auth_context
    token_auth
    json_body
    ec2_extension_v3
    s3_extension
    service_v3
  ).join(' ')
node.default['openstack']['image_api']['conf'].tap do |conf|
  conf['DEFAULT']['enable_v1_api'] = false
  conf['DEFAULT']['enable_v2_api'] = true
  if node['osl-openstack']['ceph']
    conf['DEFAULT']['show_image_direct_url'] = true
    # show_multiple_locations will be deprecated soon [1][2][3]
    # [1] https://docs.openstack.org/releasenotes/glance/newton.html#relnotes-13-0-0-origin-stable-newton
    # [2] https://docs.openstack.org/releasenotes/glance/ocata.html#relnotes-14-0-0-origin-stable-ocata-other-notes
    # [3] https://wiki.openstack.org/wiki/OSSN/OSSN-0065
    conf['DEFAULT']['show_multiple_locations'] = true
    conf['DEFAULT']['enabled_backends'] = 'cheap:rbd'
    conf['paste_deploy']['flavor'] = 'keystone'
    conf['glance_store']['default_backend'] = 'cheap'
    conf['cheap']['store_description'] = 'Cheap rbd backend'
    conf['cheap']['rbd_store_pool'] = node['osl-openstack']['image']['rbd_store_pool']
    conf['cheap']['rbd_store_user'] = node['osl-openstack']['image']['rbd_store_user']
    conf['cheap']['rbd_store_ceph_conf'] = '/etc/ceph/ceph.conf'
    conf['cheap']['rbd_store_chunk_size'] = 8
  end
end
node.default['openstack']['compute']['libvirt']['conf'].tap do |conf|
  conf['max_clients'] = '200'
  conf['max_workers'] = '200'
  conf['max_requests'] = '200'
  conf['max_client_requests'] = '50'
end
node.default['openstack']['compute']['conf'].tap do |conf|
  conf['filter_scheduler']['enabled_filters'] =
    %w(
      AggregateInstanceExtraSpecsFilter
      RetryFilter
      AvailabilityZoneFilter
      RamFilter
      ComputeFilter
      ComputeCapabilitiesFilter
      ImagePropertiesFilter
      ServerGroupAntiAffinityFilter
      ServerGroupAffinityFilter
    ).join(',')
  conf['DEFAULT'].delete('use_neutron')
  conf['DEFAULT']['instance_usage_audit'] = 'True'
  conf['DEFAULT']['instance_usage_audit_period'] = 'hour'
  conf['DEFAULT']['disk_allocation_ratio'] = 1.5
  conf['DEFAULT']['resume_guests_state_on_host_boot'] = 'True'
  conf['DEFAULT']['block_device_allocate_retries'] = 120
  conf['DEFAULT']['compute_monitors'] = 'cpu.virt_driver'
  conf['notifications']['notify_on_state_change'] = 'vm_and_task_state'
  if node['osl-openstack']['ceph']
    conf['libvirt']['disk_cachemodes'] = 'network=writeback'
    conf['libvirt']['force_raw_images'] = true
    conf['libvirt']['hw_disk_discard'] = 'unmap'
    conf['libvirt']['images_rbd_ceph_conf'] = '/etc/ceph/ceph.conf'
    conf['libvirt']['images_rbd_pool'] = node['osl-openstack']['compute']['rbd_store_pool']
    conf['libvirt']['images_type'] = 'rbd'
    conf['libvirt']['inject_key'] = false
    conf['libvirt']['inject_partition'] = '-2'
    conf['libvirt']['inject_password'] = false
    conf['libvirt']['live_migration_flag'] =
      %w(
        VIR_MIGRATE_UNDEFINE_SOURCE
        VIR_MIGRATE_PEER2PEER
        VIR_MIGRATE_LIVE
        VIR_MIGRATE_PERSIST_DEST
        VIR_MIGRATE_TUNNELLED
      ).join(',')
    conf['libvirt']['rbd_secret_uuid'] = node['ceph']['fsid-secret']
    conf['libvirt']['rbd_user'] = node['osl-openstack']['block']['rbd_store_user']
  else
    conf['libvirt']['disk_cachemodes'] = 'file=writeback,block=none'
  end
end
node.default['openstack']['network'].tap do |conf|
  conf['conf']['DEFAULT']['service_plugins'] =
    %w(
      neutron.services.l3_router.l3_router_plugin.L3RouterPlugin
      metering
    ).join(',')
  conf['conf']['DEFAULT']['allow_overlapping_ips'] = 'True'
  conf['conf']['DEFAULT']['router_distributed'] = 'False'
  conf['dnsmasq']['upstream_dns_servers'] = %w(140.211.166.130 140.211.166.131)
end
node.default['openstack']['network_l3']['conf'].tap do |conf|
  conf['DEFAULT']['interface_driver'] = 'neutron.agent.linux.interface.BridgeInterfaceDriver'
  conf['DEFAULT'].delete('external_network_bridge')
end
node.default['openstack']['network_dhcp']['conf'].tap do |conf|
  conf['DEFAULT']['interface_driver'] =
    'neutron.agent.linux.interface.BridgeInterfaceDriver'
  conf['DEFAULT']['enable_isolated_metadata'] = 'True'
  conf['DEFAULT']['dhcp_lease_duration'] = 600
end
node.default['openstack']['network_metadata']['conf'].tap do |conf|
  conf['DEFAULT']['nova_metadata_host'] = node['osl-openstack']['bind_service']
end
node.default['openstack']['network_metering']['conf'].tap do |conf|
  conf['DEFAULT']['interface_driver'] = 'neutron.agent.linux.interface.BridgeInterfaceDriver'
end
node.override['openstack']['network']['plugins']['ml2']['conf'].tap do |conf|
  conf['ml2']['type_drivers'] = 'flat,vlan,vxlan'
  conf['ml2']['extension_drivers'] = 'port_security'
  conf['ml2']['tenant_network_types'] = 'vxlan'
  conf['ml2']['mechanism_drivers'] = 'linuxbridge,l2population'
  conf['ml2_type_flat']['flat_networks'] = '*'
  conf['ml2_type_vlan']['network_vlan_ranges'] = nil
  conf['ml2_type_gre']['tunnel_id_ranges'] = '32769:34000'
  conf['ml2_type_vxlan']['vni_ranges'] = '1:1000'
end
node.default['openstack']['network']['plugins']['linuxbridge']['conf']
    .tap do |conf|
  conf['vlans']['tenant_network_type'] = 'gre,vxlan'
  conf['vlans']['network_vlan_ranges'] = nil
  conf['vxlan']['enable_vxlan'] = true
  conf['vxlan']['l2_population'] = true
  conf['agent']['polling_interval'] = 2
  conf['securitygroup']['enable_security_group'] = 'True'
  conf['securitygroup']['firewall_driver'] =
    'neutron.agent.linux.iptables_firewall.IptablesFirewallDriver'
end
node.default['openstack']['orchestration']['conf'].tap do |conf|
  conf['trustee'].delete('auth_plugin')
  conf['trustee']['auth_type'] = 'v3password'
end
node.default['openstack']['dashboard'].tap do |conf|
  conf['use_ssl'] = true
  conf['ssl']['use_data_bag'] = false
  conf['ssl']['key'] = 'wildcard.key'
  conf['ssl']['cert'] = 'wildcard.pem'
  conf['ssl']['chain'] = 'wildcard-bundle.crt'
  conf['misc_local_settings'] = {
    'LAUNCH_INSTANCE_DEFAULTS' => {
      create_volume: false,
    },
  }
end

node.default['openstack']['bind_service']['dashboard_http']['host'] = '*'
node.default['openstack']['bind_service']['dashboard_https']['host'] = '*'

node.default['openstack']['telemetry'].tap do |conf|
  conf['polling']['interval'] = 60
  conf['polling']['meters'] =
    %w(
      bandwidth
      compute.instance.booting.time
      compute.node.cpu.frequency
      compute.node.cpu.idle.percent
      compute.node.cpu.idle.time
      compute.node.cpu.iowait.percent
      compute.node.cpu.iowait.time
      compute.node.cpu.kernel.percent
      compute.node.cpu.kernel.time
      compute.node.cpu.percent
      compute.node.cpu.user.percent
      compute.node.cpu.user.time
      cpu
      cpu.delta
      cpu_l3_cache
      cpu_util
      disk.allocation
      disk.capacity
      disk.device.allocation
      disk.device.capacity
      disk.device.iops
      disk.device.latency
      disk.device.read.bytes
      disk.device.read.requests
      disk.device.read.requests.rate
      disk.device.write.bytes
      disk.device.write.requests
      disk.device.write.requests.rate
      disk.ephemeral.size
      disk.root.size
      disk.usage
      hardware.cpu.load.15min
      hardware.cpu.load.1min
      hardware.cpu.load.5min
      hardware.cpu.util
      hardware.disk.read.bytes
      hardware.disk.read.requests
      hardware.disk.size.total
      hardware.disk.size.used
      hardware.disk.write.bytes
      hardware.disk.write.requests
      hardware.memory.buffer
      hardware.memory.cached
      hardware.memory.swap.avail
      hardware.memory.swap.total
      hardware.memory.total
      hardware.memory.used
      hardware.network.incoming.bytes
      hardware.network.ip.incoming.datagrams
      hardware.network.ip.outgoing.datagrams
      hardware.network.outgoing.bytes
      hardware.network.outgoing.errors
      hardware.system_stats.cpu.idle
      hardware.system_stats.io.incoming.blocks
      hardware.system_stats.io.outgoing.blocks
      identity.authenticate.failure
      identity.authenticate.pending
      identity.authenticate.success
      identity.group.created
      identity.group.deleted
      identity.group.updated
      identity.project.created
      identity.project.deleted
      identity.project.updated
      identity.role_assignment.created
      identity.role_assignment.deleted
      identity.role.created
      identity.role.deleted
      identity.role.updated
      identity.trust.created
      identity.trust.deleted
      identity.user.created
      identity.user.deleted
      identity.user.updated
      image.download
      image.serve
      image.size
      ip.floating
      memory.bandwidth.local
      memory.bandwidth.total
      memory.resident
      memory.swap.in
      memory.swap.out
      memory.usage
      network.incoming.bytes
      network.incoming.packets
      network.incoming.packets.drop
      network.incoming.packets.error
      network.incoming.packets.rate
      network.outgoing.bytes
      network.outgoing.packets.drop
      network.outgoing.packets.error
      network.outgoing.packets.rate
      perf.cache.misses
      perf.cache.references
      perf.cpu.cycles
      perf.instructions
      port
      port.receive.bytes
      port.receive.drops
      port.receive.errors
      port.receive.packets
      port.transmit.bytes
      port.transmit.packets
      port.uptime
      snapshot.size
      stack.create
      stack.delete
      stack.resume
      stack.suspend
      stack.update
      switch
      switch.port
      switch.port.collision.count
      switch.port.receive.bytes
      switch.port.receive.crc_error
      switch.port.receive.drops
      switch.port.receive.errors
      switch.port.receive.frame_error
      switch.port.receive.overrun_error
      switch.port.receive.packets
      switch.ports
      switch.port.transmit.bytes
      switch.port.transmit.drops
      switch.port.transmit.errors
      switch.port.transmit.packets
      switch.port.uptime
      switch.table.active.entries
      vcpus
      volume
      volume.backup.size
      volume.provider.capacity.allocated
      volume.provider.capacity.free
      volume.provider.capacity.provisioned
      volume.provider.capacity.total
      volume.provider.capacity.virtual_free
      volume.provider.pool.capacity.allocated
      volume.provider.pool.capacity.free
      volume.provider.pool.capacity.provisioned
      volume.provider.pool.capacity.total
      volume.provider.pool.capacity.virtual_free
      volume.size
      volume.snapshot.size
    )
end

node.default['openstack']['telemetry']['platform'].tap do |conf|
  conf['agent_notification_packages'] = %w(openstack-ceilometer-notification)
end

node.default['openstack']['telemetry']['conf'].tap do |conf|
  conf['DEFAULT'].delete('meter_dispatchers')
end

node.default['openstack']['block-storage']['conf']['DEFAULT'].delete('glance_api_version')
node.override['openstack']['block-storage']['conf'].tap do |conf|
  conf['oslo_messaging_notifications']['driver'] = 'messagingv2'
  conf['DEFAULT']['volume_group'] = 'openstack'
  conf['DEFAULT']['volume_clear_size'] = 256
  conf['DEFAULT']['enable_v3_api'] = true
  if node['osl-openstack']['ceph']
    conf['DEFAULT']['enabled_backends'] = 'ceph,ceph_ssd'
    conf['DEFAULT']['backup_driver'] = 'cinder.backup.drivers.ceph'
    conf['DEFAULT']['backup_ceph_conf'] = '/etc/ceph/ceph.conf'
    conf['DEFAULT']['backup_ceph_user'] = node['osl-openstack']['block_backup']['rbd_store_user']
    conf['DEFAULT']['backup_ceph_chunk_size'] = 134_217_728
    conf['DEFAULT']['backup_ceph_pool'] = node['osl-openstack']['block_backup']['rbd_store_pool']
    conf['DEFAULT']['backup_ceph_stripe_unit'] = 0
    conf['DEFAULT']['backup_ceph_stripe_count'] = 0
    conf['DEFAULT']['restore_discard_excess_bytes'] = true
    conf['ceph']['volume_driver'] = 'cinder.volume.drivers.rbd.RBDDriver'
    conf['ceph']['volume_backend_name'] = 'ceph'
    conf['ceph']['rbd_pool'] = node['osl-openstack']['block']['rbd_store_pool']
    conf['ceph']['rbd_ceph_conf'] = '/etc/ceph/ceph.conf'
    conf['ceph']['rbd_flatten_volume_from_snapshot'] = false
    conf['ceph']['rbd_max_clone_depth'] = 5
    conf['ceph']['rbd_store_chunk_size'] = 4
    conf['ceph']['rados_connect_timeout'] = -1
    conf['ceph']['rbd_user'] = node['osl-openstack']['block']['rbd_store_user']
    conf['ceph']['rbd_secret_uuid'] = node['ceph']['fsid-secret']
    conf['ceph_ssd']['volume_driver'] = 'cinder.volume.drivers.rbd.RBDDriver'
    conf['ceph_ssd']['volume_backend_name'] = 'ceph_ssd'
    conf['ceph_ssd']['rbd_pool'] = node['osl-openstack']['block']['rbd_ssd_pool']
    conf['ceph_ssd']['rbd_ceph_conf'] = '/etc/ceph/ceph.conf'
    conf['ceph_ssd']['rbd_flatten_volume_from_snapshot'] = false
    conf['ceph_ssd']['rbd_max_clone_depth'] = 5
    conf['ceph_ssd']['rbd_store_chunk_size'] = 4
    conf['ceph_ssd']['rados_connect_timeout'] = -1
    conf['ceph_ssd']['rbd_user'] = node['osl-openstack']['block']['rbd_store_user']
    conf['ceph_ssd']['rbd_secret_uuid'] = node['ceph']['fsid-secret']
    conf['libvirt']['rbd_user'] = node['osl-openstack']['block']['rbd_store_user']
    conf['libvirt']['rbd_secret_uuid'] = node['ceph']['fsid-secret']
  end
end

# Dynamically find the hostname for the controller node, or use a pre-determined
# DNS name
if node['osl-openstack']['endpoint_hostname'].nil?
  if Chef::Config[:solo]
    Chef::Log.warn('This recipe uses search which Chef Solo does not support')
  else
    controller_node = search(:node, 'recipes:osl-openstack\:\:controller').first
    # Set the controller address to the public ipv4 on openstack, otherwise just
    # use the ipaddress.
    controller_address = unless controller_node.nil?
                           if controller_node['cloud']['public_ipv4'].nil?
                             controller_node['ipaddress']
                           else
                             controller_node['cloud']['public_ipv4']
                           end
                         end
    endpoint_hostname = if controller_node.nil?
                          node['ipaddress']
                        else
                          controller_address
                        end
  end
else
  endpoint_hostname = node['osl-openstack']['endpoint_hostname']
end

# Dynamically find the hostname for the network node, or use a pre-determined DNS name
if node['osl-openstack']['network_hostname'].nil? && node['osl-openstack']['separate_network_node']
  if Chef::Config[:solo]
    Chef::Log.warn('This recipe uses search which Chef Solo does not support')
  else
    network_node = search(:node, 'recipes:osl-openstack\:\:network').first
    # Set the db address to the public ipv4 on openstack, otherwise just use the
    # ipaddress.
    network_address = unless network_node.nil?
                        if network_node['cloud']['public_ipv4'].nil?
                          network_node['ipaddress']
                        else
                          network_node['cloud']['public_ipv4']
                        end
                      end
    network_hostname = if network_node.nil?
                         node['ipaddress']
                       else
                         network_address
                       end
  end
elsif node['osl-openstack']['separate_network_node']
  network_hostname = node['osl-openstack']['network_hostname']
else
  network_hostname = endpoint_hostname
end

# Dynamically find the hostname for the db node, or use a pre-determined DNS
# name
if node['osl-openstack']['db_hostname'].nil?
  if Chef::Config[:solo]
    Chef::Log.warn('This recipe uses search which Chef Solo does not support')
  else
    db_node = search(:node, 'recipes:osl-openstack\:\:ops_database').first
    # Set the db address to the public ipv4 on openstack, otherwise just use the
    # ipaddress.
    db_address = unless db_node.nil?
                   if db_node['cloud']['public_ipv4'].nil?
                     db_node['ipaddress']
                   else
                     db_node['cloud']['public_ipv4']
                   end
                 end
    db_hostname = if db_node.nil?
                    node['ipaddress']
                  else
                    db_address
                  end
  end
else
  db_hostname = node['osl-openstack']['db_hostname']
end

# Set memcache server to controller node
memcached_servers = "#{endpoint_hostname}:11211"
node.default['openstack']['memcached_servers'] = [memcached_servers]

# Set zun settings
node.default['openstack']['container']['conf']['DEFAULT']['container_runtime'] = 'nvidia'
node.override['openstack']['container']['conf']['etcd']['etcd_host'] = endpoint_hostname
node.override['openstack']['container']['conf']['websocket_proxy']['wsproxy_host'] = endpoint_hostname
node.override['openstack']['container']['conf']['websocket_proxy']['base_url'] = "wss://#{endpoint_hostname}:6784"
node.override['openstack']['container']['conf']['websocket_proxy']['ssl_only'] = 'True'
node.override['openstack']['container']['conf']['websocket_proxy']['cert'] =
  "#{node['osl-openstack']['zun_ssl_dir']}/certs/zun.pem"
node.override['openstack']['container']['conf']['websocket_proxy']['key'] =
  "#{node['osl-openstack']['zun_ssl_dir']}/private/zun.key"

# set data bag attributes with our prefix
databag_prefix = node['osl-openstack']['databag_prefix']
if databag_prefix
  node['osl-openstack']['data_bags'].each do |d|
    node.default['openstack']['secret']["#{d}_data_bag"] =
      "#{databag_prefix}_#{d}"
  end
end

%w(
  compute
  container
  block-storage
  identity
  image_api
  network
  network_dhcp
  network_l3
  network_metering
  orchestration
  telemetry
).each do |i|
  rabbit_user = node['openstack']['mq']['network']['rabbit']['userid']
  rabbit_pass = get_password 'user', rabbit_user
  rabbit_port = node['openstack']['endpoints']['mq']['port']
  node.default['openstack'][i]['conf'].tap do |conf|
    conf['oslo_messaging_notifications']['driver'] = 'messagingv2'
    conf['cache']['memcache_servers'] = memcached_servers
    conf['cache']['enabled'] = true
    conf['cache']['backend'] = 'oslo_cache.memcache_pool'
    conf['keystone_authtoken']['memcached_servers'] = memcached_servers
  end
  node.override['openstack'][i]['conf_secrets']['DEFAULT'].tap do |conf|
    conf['transport_url'] = "rabbit://#{rabbit_user}:#{rabbit_pass}@#{endpoint_hostname}:#{rabbit_port}"
  end
end

database_suffix = node['osl-openstack']['database_suffix']
node['openstack']['common']['services'].each do |service, name|
  node.default['openstack']['db'][service]['host'] = db_hostname
  node.default['openstack']['db'][service]['db_name'] =
    "#{name}_#{database_suffix}"
  node.default['openstack']['db'][service]['username'] =
    "#{name}_#{database_suffix}"
end

# Binding
node.default['openstack']['bind_service'].tap do |conf|
  conf['mq']['host'] = '0.0.0.0'
  conf['db']['host'] = '0.0.0.0'
  conf['public']['identity']['host'] = '0.0.0.0'
end

# Looping magic for endpoints and binding
%w(
  block-storage
  identity
  image_api
  compute-xvpvnc
  compute-novnc
  compute-metadata-api
  compute-vnc
  compute-vnc-proxy
  compute-api
  compute-serial-proxy
  container
  container-docker
  container-etcd
  container-wsproxy
  orchestration-api
  orchestration-api-cfn
  orchestration-api-cloudwatch
  placement-api
  telemetry
).each do |service|
  node.default['openstack']['bind_service']['all'][service]['host'] =
    node['osl-openstack']['bind_service']
  node.default['openstack']['endpoints'].tap do |conf|
    conf['db']['host'] = db_hostname
    conf['mq']['host'] = endpoint_hostname
    %w(admin public internal).each do |t|
      conf[t][service]['host'] = endpoint_hostname
    end
  end
end

node.default['openstack']['bind_service']['all']['network']['host'] =
  node['osl-openstack']['bind_service']
node.default['openstack']['endpoints'].tap do |conf|
  conf['db']['host'] = db_hostname
  conf['mq']['host'] = endpoint_hostname
  %w(admin public internal).each do |t|
    conf[t]['network']['host'] = network_hostname
  end
end

node.default['openstack']['endpoints'].tap do |conf|
  %w(admin public internal).each do |t|
    %w(compute-novnc identity).each do |s|
      conf[t][s]['scheme'] = 'https'
    end
  end
end

%w(
  compute
  container
  block-storage
  image_api
  network
  network_dhcp
  network_l3
  network_metadata
  network_metering
  orchestration
  telemetry
).each do |i|
  identity_endpoint = public_endpoint 'identity'
  auth_url = ::URI.decode identity_endpoint.to_s
  node.default['openstack'][i]['conf'].tap do |conf|
    conf['keystone_authtoken']['www_authenticate_uri'] = auth_url
    conf['keystone_authtoken']['service_token_roles_required'] = 'True'
    conf['keystone_authtoken']['service_token_roles'] = 'admin'
  end
end

yum_repository 'OSL-openpower-openstack' do
  description "OSL Openpower OpenStack repo for #{node['platform']}-#{node['platform_version'].to_i}" \
              "/openstack-#{node['openstack']['release']}"
  gpgkey 'http://ftp.osuosl.org/pub/osl/repos/yum/RPM-GPG-KEY-osuosl'
  gpgcheck true
  baseurl "http://ftp.osuosl.org/pub/osl/repos/yum/$releasever/openstack-#{node['openstack']['release']}/$basearch"
  enabled false
  only_if { node['kernel']['machine'] == 'ppc64le' }
  action :remove
end

include_recipe 'base::packages'
include_recipe 'yum-epel'

package %w(
  libffi-devel
  openssl-devel
  crudini
)

include_recipe 'firewall'
include_recipe 'selinux::permissive'
include_recipe 'yum-qemu-ev'

build_essential 'osl-openstack'

include_recipe 'openstack-common'
include_recipe 'openstack-common::logging'
include_recipe 'openstack-common::sysctl'
include_recipe 'openstack-identity::openrc'
include_recipe 'openstack-common::client'

# We're now using the packages openstack client
link '/usr/local/bin/openstack' do
  to '/opt/osc/bin/openstack'
  action :delete
end

# We need to ensure we pul in this version from the RDO repo
package 'python2-urllib3' do
  action :upgrade
end

include_recipe 'osl-ceph' if node['osl-openstack']['ceph']

# Needed for accessing neutron when running separate from controller node
package 'python-memcached'

cluster_hosts = %w(127.0.0.1)
search(:node, "role:#{node['osl-openstack']['cluster_role']}") do |n|
  cluster_hosts << n['ipaddress']
end
node.override['firewall']['range']['memcached']['4'] = cluster_hosts.flatten.sort
