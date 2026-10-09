require_relative '../../spec_helper'

describe 'osl-openstack::upgrade_runner' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      def os_node(fqdn, cloud, type, db_node: nil, recipes: [], cpu: 'POWER9', canary: nil)
        {
          'fqdn' => fqdn,
          'recipes' => recipes,
          'kernel' => { 'machine' => 'ppc64le' },
          'cpu' => { 'model_name' => cpu },
          'osl-openstack' => {
            'databag_item' => cloud, 'node_type' => type, 'db_node' => db_node, 'upgrade_canary' => canary
          },
        }
      end

      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      let(:controllers) do
        [
          os_node('c1.example.org', 'ppc64', 'controller', db_node: true),
          os_node('c2.example.org', 'ppc64', 'controller', db_node: false),
          os_node('x1.example.org', 'x86', 'controller', db_node: true),
        ]
      end
      let(:hypervisors) do
        [
          os_node('p10b.example.org', 'ppc64', 'compute', recipes: %w(osl-openstack::compute), cpu: 'POWER10'),
          os_node('p9b.example.org', 'ppc64', 'compute', recipes: %w(osl-openstack::compute)),
          os_node('p9a.example.org', 'ppc64', 'compute', recipes: %w(osl-openstack::compute)),
          os_node('p10a.example.org', 'ppc64', 'compute', recipes: %w(osl-openstack::compute), cpu: 'POWER10'),
        ]
      end

      before do
        stub_search(:node, 'osl-openstack_node_type:controller AND chef_environment:_default').and_return(controllers)
        stub_search(:node, 'recipes:osl-openstack\:\:compute AND chef_environment:_default').and_return(hypervisors)
      end

      it { is_expected.to create_directory('/etc/openstack-upgrade') }
      it { is_expected.to create_cookbook_file('/usr/local/sbin/openstack-upgrade').with(source: 'openstack-upgrade.py', mode: '0755') }

      it do
        inventory = JSON.parse(chef_run.file('/etc/openstack-upgrade/ppc64.json').content)
        expect(inventory).to include(
          'cloud' => 'ppc64',
          'controllers' => %w(c1.example.org c2.example.org),
          'db_node' => 'c1.example.org',
          'canaries' => %w(p10a.example.org p9a.example.org)
        )
        expect(inventory['hypervisors'].map { |h| h['fqdn'] }).to eq %w(p10a.example.org p10b.example.org p9a.example.org p9b.example.org)
      end

      it do
        expect(JSON.parse(chef_run.file('/etc/openstack-upgrade/x86.json').content)).to include(
          'controllers' => %w(x1.example.org), 'db_node' => 'x1.example.org', 'hypervisors' => []
        )
      end

      context 'with a hypervisor marked as the canary' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
        end

        let(:hypervisors) do
          [
            os_node('p9a.example.org', 'ppc64', 'compute', recipes: %w(osl-openstack::compute)),
            os_node('p9b.example.org', 'ppc64', 'compute', recipes: %w(osl-openstack::compute), canary: true),
          ]
        end

        it { expect(JSON.parse(chef_run.file('/etc/openstack-upgrade/ppc64.json').content)['canaries']).to eq %w(p9b.example.org) }
      end
    end
  end
end
