require 'serverspec'

set :backend, :exec

describe package('nagios-plugins-openstack') do
  it { should_not be_installed }
end

describe file('/usr/lib64/nagios/plugins/check_openstack') do
  its(:content) { should match(%r{/usr/lib64/nagios/plugins/\$\{@\}}) }
  it { should be_mode 755 }
end

describe file('/etc/sudoers.d/nrpe-openstack') do
  its(:content) do
    should match(%r{%nrpe ALL=\(root\) NOPASSWD:/usr/lib64/nagios/plugins/check_openstack})
  end
end

%w(
  check_nova_services
  check_nova_hypervisors
  check_nova_images
  check_neutron_agents
  check_cinder_services
).each do |check|
  describe file("/etc/nagios/nrpe.d/#{check}.cfg") do
    it { should_not exist }
  end
end

%w(
  check_cinder_api
  check_glance_api
  check_keystone_api
  check_neutron_api
  check_neutron_floating_ip
  check_nova_api
).each do |check|
  describe file("/etc/nagios/nrpe.d/#{check}.cfg") do
    its(:content) do
      should match(%r{command\[#{check}\]=/bin/sudo /usr/lib64/nagios/plugins/check_openstack #{check}})
    end
  end
end
