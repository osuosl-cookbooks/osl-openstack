# Valkey + sentinel coverage for the shared coordination (tooz lock)
# tier. Defaults cover the single-node kitchen suite; the multi-node env
# passes cluster_size 3 via mq.yml to also assert replication and
# sentinel quorum.
cluster_size = input('cluster_size', value: 1)
service_name = input('coordination_service_name', value: 'oslocks')
valkey_pass = input('valkey_pass', value: 'oslocks')
# Set only by the single-node suite (the multi-node mq systems don't
# run osl-openstack::mon).
nrpe_checks = input('nrpe_checks', value: false)

control 'coordination_tier' do
  %w(valkey valkey-sentinel).each do |svc|
    describe service(svc) do
      it { should be_enabled }
      it { should be_running }
    end
  end

  describe port(6379) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
  end
  describe port(26379) do
    it { should be_listening }
    its('protocols') { should include 'tcp' }
  end

  # Chef-seeded config: no eviction (an evicted key is a silently
  # released lock) and AOF persistence (held locks survive a restart).
  describe file('/etc/valkey/valkey.conf') do
    its('content') { should match(/^maxmemory-policy noeviction$/) }
    its('content') { should match(/^appendonly yes$/) }
  end

  # Unauthenticated access must be refused, the configured password
  # accepted.
  describe command('valkey-cli ping') do
    its('stdout') { should match(/NOAUTH/) }
  end
  describe command("valkey-cli -a '#{valkey_pass}' --no-auth-warning ping") do
    its('stdout') { should match(/^PONG$/) }
  end

  # Sentinel monitors the service and can reach quorum + failover
  # authorization with the sentinels it sees.
  describe command("valkey-cli -p 26379 sentinel ckquorum #{service_name}") do
    its('exit_status') { should eq 0 }
    its('stdout') { should match(/OK #{cluster_size} usable Sentinels/) }
  end

  # Operator tooling from osl-valkey sees a healthy service end to end.
  describe command('/usr/local/bin/valkey-status') do
    its('exit_status') { should eq 0 }
    its('stdout') { should match(/ckquorum: OK/) }
  end

  if cluster_size > 1
    # Every member is the primary or a replica of it.
    describe command("valkey-cli -a '#{valkey_pass}' --no-auth-warning info replication") do
      its('stdout') { should match(/^role:(master|slave)/) }
    end
    # Any sentinel reports the full replica set.
    describe command("valkey-cli -p 26379 sentinel master #{service_name}") do
      its('stdout') { should match(/num-slaves\s+#{cluster_size - 1}\s/) }
    end
  end

  # NRPE checks from osl-openstack::mon, run exactly as NRPE would (as
  # the nrpe user, through its sudo grant where the check needs one).
  if nrpe_checks
    %w(
      check_valkey
      check_valkey_replication
      check_valkey_sentinel
    ).each do |chk|
      describe file("/etc/nagios/nrpe.d/#{chk}.cfg") do
        it { should exist }
      end
    end

    describe command('sudo -u nrpe sudo /usr/lib64/nagios/plugins/check_valkey') do
      its('exit_status') { should eq 0 }
      its('stdout') { should match(/^VALKEY OK/) }
    end
    describe command("sudo -u nrpe sudo /usr/lib64/nagios/plugins/check_valkey_replication #{cluster_size}") do
      its('exit_status') { should eq 0 }
      its('stdout') { should match(/^VALKEY REPLICATION OK/) }
    end
    describe command("sudo -u nrpe /usr/lib64/nagios/plugins/check_valkey_sentinel #{service_name} #{cluster_size}") do
      its('exit_status') { should eq 0 }
      its('stdout') { should match(/^VALKEY SENTINEL OK/) }
    end
  end
end
