if defined?('ChefSpec')
  def add_nrpe_check(resource_name)
    ChefSpec::Matchers::ResourceMatcher.new(:nrpe_check,
                                            :add,
                                            resource_name)
  end

  def remove_nrpe_check(resource_name)
    ChefSpec::Matchers::ResourceMatcher.new(:nrpe_check,
                                            :remove,
                                            resource_name)
  end

  def create_ssh_user_private_key(resource_name)
    ChefSpec::Matchers::ResourceMatcher.new(:ssh_user_private_key,
                                            :create,
                                            resource_name)
  end

  def delete_ssh_user_private_key(resource_name)
    ChefSpec::Matchers::ResourceMatcher.new(:ssh_user_private_key,
                                            :delete,
                                            resource_name)
  end

  def add_ssh_util_config(resource_name)
    ChefSpec::Matchers::ResourceMatcher.new(:ssh_util_config,
                                            :add,
                                            resource_name)
  end

  def remove_ssh_util_config(resource_name)
    ChefSpec::Matchers::ResourceMatcher.new(:ssh_util_config,
                                            :remove,
                                            resource_name)
  end
end
