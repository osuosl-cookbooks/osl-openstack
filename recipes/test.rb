secret = Chef::EncryptedDataBagItem.load_secret("/etc/chef/encrypted_data_bag_secret")

ssh_key = Chef::EncryptedDataBagItem.load("ssh-keys", "packstack-root", secret)

template "/tmp/databag" do
  variables(:key => ssh_key['id_rsa'])
  owner "root"
  mode "600"
  source "id_rsa.erb"
end
