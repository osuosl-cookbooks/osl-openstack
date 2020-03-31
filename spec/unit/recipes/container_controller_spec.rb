require_relative '../../spec_helper'

describe 'osl-openstack::container_controller' do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS)
  end
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'common_stubs'
  include_context 'identity_stubs'
  include_context 'container_stubs'
  it 'converges successfully' do
    expect { chef_run }.to_not raise_error
  end
  describe '/etc/zun/zun.conf' do
    let(:file) { chef_run.template('/etc/zun/zun.conf') }
    [
      /^host = 10.0.0.2$/,
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name).with_section_content('api', line)
      end
    end
    it do
      expect(chef_run).to create_iptables_ng_rule('etcd_ipv4')
        .with(
          rule:
            [
              '--protocol tcp --source 127.0.0.1 --destination-port 2379 --jump ACCEPT',
              '--protocol tcp --source 127.0.0.1 --destination-port 2380 --jump ACCEPT',
              '--protocol tcp --source 127.0.0.1 --destination-port 4001 --jump ACCEPT',
              '--protocol tcp --source 127.0.0.1 --destination-port 7001 --jump ACCEPT',
              '--protocol tcp --source 192.168.1.100 --destination-port 2379 --jump ACCEPT',
              '--protocol tcp --source 192.168.1.100 --destination-port 2380 --jump ACCEPT',
              '--protocol tcp --source 192.168.1.100 --destination-port 4001 --jump ACCEPT',
              '--protocol tcp --source 192.168.1.100 --destination-port 7001 --jump ACCEPT',
            ]
        )
    end
    context 'Set bind_service' do
      let(:runner) do
        ChefSpec::SoloRunner.new(REDHAT_OPTS)
      end
      let(:node) { runner.node }
      cached(:chef_run) { runner.converge(described_recipe) }
      include_context 'common_stubs'
      [
        /^host = 10.0.0.10$/,
      ].each do |line|
        it do
          node.override['osl-openstack']['bind_service'] = '10.0.0.10'
          expect(chef_run).to render_config_file(file.name).with_section_content('api', line)
        end
      end
    end
  end
end
