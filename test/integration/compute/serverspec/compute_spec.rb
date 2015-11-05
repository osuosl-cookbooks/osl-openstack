require 'serverspec'

set :backend, :exec

describe kernel_module('tun') do
  it { should be_loaded }
end
