describe yum.repo('RDO-newton') do
  it { should_not exist }
  it { should_not be_enabled }
end

describe yum.repo('RDO-ocata') do
  it { should exist }
  it { should be_enabled }
end

describe file('/root/upgrade.sh') do
  it { should be_executable }
end