source 'https://supermarket.osuosl.org'
source 'https://supermarket.chef.io'

solver :ruby, :required

cookbook 'openstack_test', path: 'test/cookbooks/openstack_test'

# TEMPORARY until osl-repos#62 and osl-apache#207 release
cookbook 'osl-repos', git: 'git@github.com:osuosl-cookbooks/osl-repos', branch: 'openstack-osuosl-source'
cookbook 'osl-apache', git: 'git@github.com:osuosl-cookbooks/osl-apache', branch: 'mod_proxy_uwsgi'

metadata
