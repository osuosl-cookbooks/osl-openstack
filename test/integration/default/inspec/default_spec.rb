baseurl =
  if os.arch == 'x86_64'
    'http://centos.osuosl.org/7/cloud/x86_64/openstack-rocky/'
  elsif os.arch == 'ppc64le'
    'http://centos-altarch.osuosl.org/7/cloud/ppc64le/openstack-rocky/'
  end

describe yum.repo('RDO-rocky') do
  it { should exist }
  it { should be_enabled }
  its('baseurl') { should cmp baseurl }
end

describe yum.repo('OSL-openpower-openstack') do
  it { should_not exist }
  it { should_not be_enabled }
end

describe file('/root/openrc') do
  its(:content) do
    should match(%r{
export OS_USERNAME=admin
export OS_USER_DOMAIN_NAME=default
export OS_PASSWORD=admin
export OS_PROJECT_NAME=admin
export OS_PROJECT_DOMAIN_NAME=default
export OS_IDENTITY_API_VERSION=3
export OS_AUTH_URL=https://controller.example.com:5000/v3
export OS_REGION_NAME=RegionOne

# Misc options
export OS_CACERT="/etc/ssl/certs/ca-bundle.crt"
export OS_AUTH_TYPE=password})
  end
end

describe file('/root/openrc') do
  its(:content) { should_not match(%r{OS_AUTH_URL=http://127.0.0.1/v2.0}) }
end

describe file('/etc/sysconfig/iptables-config') do
  its(:content) { should match(/^IPTABLES_SAVE_ON_STOP="no"$/) }
  its(:content) { should match(/^IPTABLES_SAVE_ON_RESTART="no"$/) }
end

describe file('/usr/local/bin/openstack') do
  it { should_not exist }
end

describe command('/usr/bin/openstack -h') do
  its(:exit_status) { should eq 0 }
end
