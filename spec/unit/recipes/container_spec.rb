require_relative '../../spec_helper'

describe 'osl-openstack::container' do
  let(:runner) { ChefSpec::SoloRunner.new(REDHAT_OPTS) }
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  include_context 'container_stubs'
  it 'converges successfully' do
    expect { chef_run }.to_not raise_error
  end
  it do
    expect(chef_run).to create_iptables_ng_rule('docker_ipv4').with(
      rule: [
        '--protocol tcp --source 10.0.0.10 --destination-port 2375 --jump ACCEPT',
        '--protocol tcp --source 10.0.0.10 --destination-port 2376 --jump ACCEPT',
        '--protocol tcp --source 10.0.0.11 --destination-port 2375 --jump ACCEPT',
        '--protocol tcp --source 10.0.0.11 --destination-port 2376 --jump ACCEPT',
        '--protocol tcp --source 127.0.0.1 --destination-port 2375 --jump ACCEPT',
        '--protocol tcp --source 127.0.0.1 --destination-port 2376 --jump ACCEPT',
        '--protocol tcp --source 192.168.99.10 --destination-port 2375 --jump ACCEPT',
        '--protocol tcp --source 192.168.99.10 --destination-port 2376 --jump ACCEPT',
      ]
    )
  end
end
