# Suites that set osl-selinux enforcing prove osuosl-openstack-selinux before production does
control 'selinux' do
  describe command('getenforce') do
    its('stdout') { should cmp "Enforcing\n" }
  end

  # osuosl-openstack-selinux turns on upstream's tunables for privsep-helper and dnsmasq
  %w(os_neutron_dac_override os_dnsmasq_dac_override).each do |b|
    describe command("getsebool #{b}") do
      its('stdout') { should match /--> on$/ }
    end
  end

  # Only denials that blocked something; permissive domains like ceph_t log too.
  # --input-logs, because without a tty ausearch reads the verifier's stdin and hangs
  describe command("ausearch --input-logs -m AVC,USER_AVC -ts boot | grep 'permissive=0'") do
    its('stdout') { should eq '' }
  end

  # The domain RDO's /usr/bin twin of each venv daemon ran in
  {
    'nova-compute' => 'virtd_t',
    'nova-conductor' => 'nova_t',
    'nova-scheduler' => 'nova_t',
    'nova-novncproxy' => 'nova_t',
    'neutron-server' => 'neutron_t',
    'neutron-dhcp-agent' => 'neutron_t',
    'neutron-l3-agent' => 'neutron_t',
    'neutron-linuxbridge-agent' => 'neutron_t',
    'neutron-metadata-agent' => 'neutron_t',
    'glance-api' => 'glance_api_t',
    'cinder-volume' => 'cinder_volume_t',
    'cinder-scheduler' => 'cinder_scheduler_t',
    'uwsgi' => 'httpd_t',
  }.each do |bin, domain|
    describe processes(%r{/opt/openstack/[^/]+/bin/#{bin}( |$)}) do
      its('labels') { should all(match(/:#{domain}:/)) }
    end
  end
end
