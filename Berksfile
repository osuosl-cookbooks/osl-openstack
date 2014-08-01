source 'https://supermarket.getchef.com'

# OSL Base deps
cookbook "base", git: "git@github.com:osuosl-cookbooks/base"
cookbook "omnibus_updater"
cookbook "aliases", git: "git@github.com:osuosl-cookbooks/aliases"
cookbook "firewall", git: "git@github.com:osuosl-cookbooks/firewall"
cookbook "nagios", git: "git@github.com:osuosl-cookbooks/nagios"
cookbook "monitoring", git: "git@github.com:osuosl-cookbooks/monitoring"
cookbook "munin"
cookbook "osl-munin", git: "git@github.com:osuosl-cookbooks/osl-munin"
cookbook "osl-nginx", git: "git@github.com:osuosl-cookbooks/osl-nginx"
cookbook "osl-apache", git: "git@github.com:osuosl-cookbooks/osl-apache"
cookbook "runit", "1.5.10"
cookbook "yum", ">= 3.1.4"
cookbook "yum-epel", ">= 0.3.4"
cookbook "apt", ">= 2.3.8"
cookbook "database", ">= 2.0.0"
cookbook "statsd", github: "att-cloud/cookbook-statsd"

# Openstack deps
#cookbook "mysql", "~> 4.1"
%w(openstack-block-storage openstack-common
openstack-object-storage openstack-ops-database openstack-ops-messaging
openstack-orchestration openstack-telemetry openstack-identity openstack-image
openstack-network openstack-compute openstack-dashboard).each do |cb|
  cookbook cb,
    github: "stackforge/cookbook-#{cb}",
    branch: "stable/icehouse"
end

metadata
