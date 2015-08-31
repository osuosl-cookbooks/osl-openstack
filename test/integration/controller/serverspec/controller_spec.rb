require 'serverspec'

set :backend, :exec

describe command('/opt/tempest/run_tests.sh -V') do
  its(:exit_status) { should eq 0 }
end
