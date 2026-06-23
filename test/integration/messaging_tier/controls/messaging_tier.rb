# Broker coverage for the shared messaging tier. Defaults cover the
# single-node kitchen suite; the multi-node env passes inputs
# (vhost/vhost_user/cluster_size/cmr_target_group_size) to also assert
# clustering + CMR.
vhost = input('vhost', value: 'tier-test')
vhost_user = input('vhost_user', value: 'tier')
cluster_size = input('cluster_size', value: 1)
cmr_target_group_size = input('cmr_target_group_size', value: 0)

control 'messaging_tier' do
  describe service('rabbitmq-server') do
    it { should be_enabled }
    it { should be_running }
  end

  # tls_only: AMQPS on 5671 up, plaintext 5672 listener gone.
  describe port(5671) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
  end
  describe port(5672) do
    it { should_not be_listening }
  end

  # rabbitmq.conf: TLS ssl_options + tls_only.
  describe file('/etc/rabbitmq/rabbitmq.conf') do
    it { should exist }
    its('content') { should match(/^listeners\.ssl\.default = 5671$/) }
    its('content') { should match(%r{^ssl_options\.certfile = /etc/rabbitmq/ssl/certs/cert\.pem$}) }
    its('content') { should match(%r{^ssl_options\.keyfile = /etc/rabbitmq/ssl/private/key\.pem$}) }
    its('content') { should match(/^listeners\.tcp = none$/) }
  end

  # CMR config, multi-node tier only (new members auto-join quorum queues).
  if cmr_target_group_size > 0
    describe file('/etc/rabbitmq/rabbitmq.conf') do
      its('content') { should match(/^quorum_queue\.continuous_membership_reconciliation\.enabled = true$/) }
      its('content') { should match(/^quorum_queue\.continuous_membership_reconciliation\.target_group_size = #{cmr_target_group_size}$/) }
    end
  end

  # Wildcard cert deployed rabbitmq-readable for the TLS listener.
  describe file('/etc/rabbitmq/ssl/private/key.pem') do
    it { should exist }
    it { should be_owned_by 'rabbitmq' }
  end

  # Multi-node: all members clustered and online. (The vhost check below
  # is an implicit cluster test - it only reaches a secondary via Khepri.)
  if cluster_size > 1
    describe command("rabbitmqctl -t 60 await_online_nodes #{cluster_size}") do
      its('exit_status') { should eq 0 }
    end
  end

  # Per-cloud vhost + user with vhost-scoped permissions.
  describe command('rabbitmqctl -q list_vhosts') do
    its('stdout') { should match(/^#{Regexp.escape(vhost)}$/) }
  end
  describe command("rabbitmqctl -q list_permissions -p #{vhost}") do
    its('stdout') { should match(/^#{Regexp.escape(vhost_user)}\s+\.\*\s+\.\*\s+\.\*/) }
  end

  # Multi-node: the services must declare quorum queues in the vhost.
  # Assert one is present, not the absence of classic (reply/fanout
  # queues are legitimately classic).
  if cmr_target_group_size > 0
    describe command("rabbitmqctl -q list_queues -p #{vhost} type") do
      its('exit_status') { should eq 0 }
      its('stdout') { should match(/^quorum$/) }
    end
  end
end
