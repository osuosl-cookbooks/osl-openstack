node.default['prometheus-platform']['components']['prometheus']['config']['scrape_configs'].tap do |c|
  c['index_1'] = {
    'job_name' => 'openstack',
    'honor_labels' => true,
    'static_configs' => {
      'index_1' => {
        'targets' => %w(controller.testing.osuosl.org:9183),
        'labels' => {},
      },
    },
  }
end

include_recipe 'osl-prometheus::server'
