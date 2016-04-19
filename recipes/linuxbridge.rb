link '/etc/neutron/plugins/ml2/linuxbridge_agent.ini' do
  to '/etc/neutron/plugins/linuxbridge/linuxbridge_conf.ini'
  notifies :restart, 'service[neutron-plugin-linuxbridge-agent]'
end
