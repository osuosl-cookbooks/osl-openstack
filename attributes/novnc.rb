default['openstack']['novnc']['ssl']['use_ssl'] = true

# Location of ssl cert and key to use
default['openstack']['novnc']['ssl']['dir'] = '/etc/ssl/nova'

# Name of ssl certificate for nova-novncproxy to use
default['openstack']['novnc']['ssl']['cert'] = 'nova.pem'
default['openstack']['novnc']['ssl']['key']  = 'nova.key'

# Remote uri for the certificate and key
# This assumes the certificate::wildcard recipe was run beforehand
default['openstack']['novnc']['ssl']['cert_url'] = nil
default['openstack']['novnc']['ssl']['key_url'] = nil
