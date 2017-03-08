require 'serverspec'

set :backend, :exec

describe file('/etc/httpd/conf.d/neo.conf') do
  it { should exist }
end

%w(
  neo-controller
  neo-provider-ac
  neo-provider-common
  neo-provider-discovery
  neo-provider-dm
  neo-provider-ethdisc
  neo-provider-ib
  neo-provider-monitor
  neo-provider-performance
  neo-provider-provisioning
  neo-provider-solution
  neo-provider-virtualization
).each do |p|
  describe package(p) do
    it { should be_installed }
  end
end

%w(
  neo-access-credentials
  neo-controller
  neo-device-manager
  neo-eth-discovery
  neo-ib
  neo-ip-discovery
  neo-monitor
  neo-performance
  neo-provisioning
  neo-solution
  neo-virtualization
).each do |s|
  describe service(s) do
    it { should be_enabled }
    it { should be_running }
  end
end

%w(80 443).each do |p|
  describe port(p) do
    it { should be_listening }
  end
end

curl_cmd = 'curl -v -H "Host: neo.osuosl.org" -k -o /dev/null -s'

describe command("#{curl_cmd} http://127.0.0.1/ 2>&1") do
  its(:stdout) { should match(%r{^< Location: https://neo.osuosl.org/}) }
  its(:stdout) { should match(%r{^< HTTP/1.1 302 Found}) }
end

describe command("#{curl_cmd} https://127.0.0.1/ 2>&1") do
  its(:stdout) { should match(%r{^< Location: https://neo.osuosl.org/neo/}) }
  its(:stdout) { should match(%r{^< HTTP/1.1 302 Found}) }
end

describe command("#{curl_cmd} https://127.0.0.1/neo/ 2>&1") do
  its(:stdout) { should match(%r{^< Location: https://neo.osuosl.org/neo/login\?next=%2Fneo%2F}) }
  its(:stdout) { should match(/^< Set-Cookie: session=/) }
end
