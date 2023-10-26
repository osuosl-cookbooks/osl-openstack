osl_fakenic 'eth1' do
  notifies :reload, 'ohai[reload]', :immediately
end

osl_fakenic 'eth2' do
  notifies :reload, 'ohai[reload]', :immediately
end

ohai 'reload' do
  action :nothing
end
