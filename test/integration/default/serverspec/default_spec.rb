require 'serverspec'

set :backend, :exec

describe yumrepo('RDO-newton') do
  it { should exist }
  it { should be_enabled }
end

describe file('/etc/yum.repos.d/epel.repo') do
  its(:content) { should match(/^exclude=zeromq\*$/) }
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
export OS_REGION_NAME=RegionOne})
  end
end

describe file('/root/openrc') do
  its(:content) { should_not match(%r{OS_AUTH_URL=http://127.0.0.1/v2.0}) }
end

describe file('/etc/sysconfig/iptables-config') do
  its(:content) { should match(/^IPTABLES_SAVE_ON_STOP="no"$/) }
  its(:content) { should match(/^IPTABLES_SAVE_ON_RESTART="no"$/) }
end

describe command('/usr/local/bin/openstack -h') do
  its(:exit_status) { should eq 0 }
end
