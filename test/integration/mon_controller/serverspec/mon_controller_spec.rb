require 'serverspec'

set :backend, :exec

describe package('nagios-plugins-openstack') do
  it { should be_installed }
end

describe file('/usr/lib64/nagios/plugins/check_openstack') do
  its(:content) { should match(%r{/usr/lib64/nagios/plugins/\$\{@\}}) }
  it { should be_mode 755 }
end

describe file('/etc/sudoers.d/nrpe-openstack') do
  its(:content) do
    should match(%r{%nrpe ALL=\(root\) \
NOPASSWD:/usr/lib64/nagios/plugins/check_openstack})
  end
end

describe file('/etc/nagios/nrpe.d/check_nova_services.cfg') do
  its(:content) do
    should match(%r{command\[check_nova_services\]=/bin/sudo \
/usr/lib64/nagios/plugins/check_openstack check_nova-services -w 5: -c 4:})
  end
end

describe file('/etc/nagios/nrpe.d/check_nova_hypervisors.cfg') do
  its(:content) do
    should match(%r{command\[check_nova_hypervisors\]=/bin/sudo \
/usr/lib64/nagios/plugins/check_openstack check_nova-hypervisors \
--warn_memory_percent 0:80 --critical_memory_percent 0:90 \
--warn_vcpus_percent 0:80 --critical_vcpus_percent 0:90})
  end
end

describe file('/etc/nagios/nrpe.d/check_nova_images.cfg') do
  its(:content) do
    should match(%r{command\[check_nova_images\]=/bin/sudo \
/usr/lib64/nagios/plugins/check_openstack check_nova-images -w 1 -c 2})
  end
end

describe file('/etc/nagios/nrpe.d/check_neutron_agents.cfg') do
  its(:content) do
    should match(%r{command\[check_neutron_agents\]=/bin/sudo \
/usr/lib64/nagios/plugins/check_openstack check_neutron-agents -w 5: -c 4:})
  end
end

describe file('/etc/nagios/nrpe.d/check_cinder_services.cfg') do
  its(:content) do
    should match(%r{command\[check_cinder_services\]=/bin/sudo \
/usr/lib64/nagios/plugins/check_openstack check_cinder-services -w 3: -c 2:})
  end
end

describe file('/etc/nagios/nrpe.d/check_keystone_token.cfg') do
  its(:content) do
    should match(%r{command\[check_keystone_token\]=/bin/sudo \
/usr/lib64/nagios/plugins/check_openstack check_keystone-token})
  end
end
