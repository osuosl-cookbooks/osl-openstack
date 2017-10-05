require 'serverspec'

set :backend, :exec

describe command('source /root/openrc && openstack stack create -t /tmp/heat.yml stack') do
  its(:exit_status) { should eq 0 }
end

describe command('source /root/openrc && openstack stack show stack -c stack_status -f value') do
  its(:exit_status) { should eq 0 }
  its(:stdout) { should match(/^CREATE_IN_PROGRESS|CREATE_COMPLETE$/) }
end
