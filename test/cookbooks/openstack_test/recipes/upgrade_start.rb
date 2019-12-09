execute 'systemctl start httpd'

file '/root/upgrade-test' do
  action :touch
end
