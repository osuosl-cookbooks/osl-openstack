require 'serverspec'

set :backend, :exec

describe command('scl enable python27 "/opt/tempest/run_tests.sh -V"') do
  its(:exit_status) { should eq 0 }
end
