require_relative '../../spec_helper'

describe 'osl-openstack::ops_coordination' do
  # The coordination tier runs on the EL10 mq nodes only, so other
  # platforms are deliberately not tested. The valkey/sentinel
  # mechanics (configs, services, firewall) are covered by the
  # osl-valkey cookbook's own specs; here we assert the data bag to
  # resource mapping.
  [ALMA_10].each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm.dup.merge(
          step_into: %w(osl_openstack_coordination)
        )).converge(described_recipe)
      end

      include_context 'common_stubs'

      # Single standalone node, like the messaging_tier kitchen suite.
      before do
        stub_data_bag_item('openstack', 'x86').and_return(
          openstack_secrets_stub.merge('coordination' => { 'pass' => 'oslocks' })
        )
      end

      it { is_expected.to create_osl_openstack_coordination('default').with(pass: 'oslocks') }
      it do
        is_expected.to create_osl_valkey('coordination').with(
          pass: 'oslocks',
          replicaof: nil,
          appendonly: true,
          maxmemory_policy: 'noeviction',
          min_replicas_to_write: nil,
          config_version: 1
        )
      end
      it do
        is_expected.to create_osl_valkey_sentinel('oslocks').with(
          monitor_host: '127.0.0.1',
          quorum: 1,
          pass: 'oslocks',
          down_after_ms: 5000,
          failover_timeout_ms: 60_000
        )
      end

      context 'tier primary' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.dup.merge(
            step_into: %w(osl_openstack_coordination)
          )) { |node| node.automatic['hostname'] = 'mq1' }.converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            openstack_secrets_stub.merge(
              'coordination' => {
                'endpoint' => %w(
                  mq1.testing.osuosl.org
                  mq2.testing.osuosl.org
                  mq3.testing.osuosl.org
                ),
                'primary' => 'mq1.testing.osuosl.org',
                'pass' => 'oslocks',
              }
            )
          )
        end

        it do
          is_expected.to create_osl_valkey('coordination').with(
            replicaof: nil,
            min_replicas_to_write: 1
          )
        end
        it do
          is_expected.to create_osl_valkey_sentinel('oslocks').with(
            monitor_host: 'mq1.testing.osuosl.org',
            quorum: 2
          )
        end
      end

      context 'tier replica' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.dup.merge(
            step_into: %w(osl_openstack_coordination)
          )) { |node| node.automatic['hostname'] = 'mq2' }.converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            openstack_secrets_stub.merge(
              'coordination' => {
                'endpoint' => %w(
                  mq1.testing.osuosl.org
                  mq2.testing.osuosl.org
                  mq3.testing.osuosl.org
                ),
                'primary' => 'mq1.testing.osuosl.org',
                'pass' => 'oslocks',
              }
            )
          )
        end

        it do
          is_expected.to create_osl_valkey('coordination').with(
            replicaof: 'mq1.testing.osuosl.org',
            min_replicas_to_write: 1
          )
        end
        it do
          is_expected.to create_osl_valkey_sentinel('oslocks').with(
            monitor_host: 'mq1.testing.osuosl.org',
            quorum: 2
          )
        end
      end

      context 'custom tuning' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.dup.merge(
            step_into: %w(osl_openstack_coordination)
          )).converge(described_recipe)
        end

        before do
          stub_data_bag_item('openstack', 'x86').and_return(
            openstack_secrets_stub.merge(
              'coordination' => {
                'pass' => 'oslocks',
                'service_name' => 'oslocks2',
                'down_after_ms' => 10_000,
                'config_version' => 3,
              }
            )
          )
        end

        it { is_expected.to create_osl_valkey('coordination').with(config_version: 3) }
        it do
          is_expected.to create_osl_valkey_sentinel('oslocks2').with(
            down_after_ms: 10_000,
            config_version: 3
          )
        end
      end
    end
  end
end
