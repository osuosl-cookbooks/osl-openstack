resource_name :osl_openstack_coordination
provides :osl_openstack_coordination
default_action :create
unified_mode true

# Shared valkey + sentinel service on the mq tier, providing tooz
# distributed locks ([coordination] backend_url) for the clouds via the
# redis:// driver. One valkey per tier node (one primary, the rest
# replicas), sentinel on every node handling primary failover. The
# valkey/sentinel mechanics live in the osl-valkey cookbook; this
# resource only maps the tier topology (data bag driven) onto it.

property :pass, String, sensitive: true, required: true

# All tier node FQDNs; sizes the sentinel quorum ((N/2)+1). Empty =
# standalone single node (the kitchen suite).
property :nodes, Array, default: []

# FQDN of the initial primary; absent = this node is a standalone
# primary. Replicas are any node whose short hostname doesn't match.
property :primary, String

# Sentinel master name; clouds reference it in their backend_url.
property :service_name, String, default: 'oslocks'

property :down_after_ms, Integer, default: 5000
property :failover_timeout_ms, Integer, default: 60000

# Passed through to the seed-once configs in osl-valkey; bump to force
# a re-seed + restart (also resets failover state to the seeded
# topology, so treat as a maintenance action).
property :config_version, Integer, default: 1

action :create do
  # Short-hostname compare, exact match (mq1 vs mq10), mirroring the
  # rabbitmq primary detection.
  primary_node = new_resource.primary
  replica = primary_node && primary_node.split('.', 2).first != node['hostname']
  clustered = new_resource.nodes.count > 1
  quorum = clustered ? (new_resource.nodes.count / 2) + 1 : 1

  # 6379/26379 are opened OSL-only by the osl-valkey resources. tooz
  # 2.10.1 (yoga) has no sentinel auth support, so the firewall is the
  # only guard on sentinel; valkey itself requires the password.
  osl_valkey 'coordination' do
    pass new_resource.pass
    replicaof primary_node if replica
    # An evicted key is a silently released lock; held locks must
    # survive a restart.
    maxmemory_policy 'noeviction'
    appendonly true
    # On the tier, a primary that loses both replicas goes read-only
    # rather than granting locks the rest of the cluster cannot see.
    min_replicas_to_write 1 if clustered
    config_version new_resource.config_version
  end

  osl_valkey_sentinel new_resource.service_name do
    monitor_host primary_node || '127.0.0.1'
    quorum quorum
    pass new_resource.pass
    down_after_ms new_resource.down_after_ms
    failover_timeout_ms new_resource.failover_timeout_ms
    config_version new_resource.config_version
  end
end
