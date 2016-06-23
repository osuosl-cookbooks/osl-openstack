require 'serverspec'

set :backend, :exec

describe yumrepo('RDO-mitaka') do
  it { should exist }
  it { should be_enabled }
end

describe file('/root/openrc') do
  its(:content) do
    should match(%r{
export OS_USERNAME=admin
export OS_PASSWORD=admin
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://.*:5000/v2.0
export OS_REGION_NAME=RegionOne})
  end
end

describe file('/root/openrc') do
  its(:content) { should_not match(%r{OS_AUTH_URL=http://127.0.0.1/v2.0}) }
end
