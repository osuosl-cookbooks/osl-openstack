#!/usr/bin/env ruby
require 'fog/openstack'
require 'prometheus_reporter'

@connection_params = {
  openstack_auth_url:     ENV['OS_AUTH_URL'],
  openstack_username:     ENV['OS_USERNAME'],
  openstack_api_key:      ENV['OS_PASSWORD'],
  openstack_project_name: ENV['OS_PROJECT_NAME'],
  openstack_domain_id:    'default',
}

report = PrometheusReporter::TextFormatter.new

report.help(:openstack_start_time, 'Start timestamp')
report.type(:openstack_start_time, :gauge)
report.help(:openstack_instances, 'VM instances')
report.type(:openstack_instances, :gauge)
report.help(:openstack_projects, 'Enabled projects')
report.type(:openstack_projects, :gauge)
report.help(:openstack_completion_time, 'Stop timestamp')
report.type(:openstack_completion_time, :gauge)

report.entry(:openstack_start_time, value: Time.now.to_i, labels: { cluster: ENV['OS_CLUSTER'] })

compute = Fog::OpenStack::Compute.new(@connection_params)
instances = compute.servers.all({ 'all_tenants' => true })

instances.each do |i|
  report.entry(
    :openstack_instances,
    value: i.state == 'ACTIVE' ? 1 : 0,
    labels: {
      cluster: ENV['OS_CLUSTER'],
      id: i.id,
      name: i.name,
      state: i.state,
      power_state: i.os_ext_sts_power_state,
      host: i.os_ext_srv_attr_host,
      tenant_id: i.tenant_id,
      user_id: i.user_id,
    }
  )
end

identity = Fog::OpenStack::Identity.new(@connection_params)
projects = identity.projects

projects.each do |p|
  report.entry(
    :openstack_projects,
    value: p.enabled ? 1 : 0,
    labels: {
      cluster: ENV['OS_CLUSTER'],
      id: p.id,
      name: p.name,
    }
  )
end

report.entry(:openstack_completion_time, value: Time.now.to_i, labels: { cluster: ENV['OS_CLUSTER'] })

puts report.to_s
