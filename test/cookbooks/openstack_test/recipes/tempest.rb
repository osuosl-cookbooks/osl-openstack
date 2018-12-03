include_recipe 'openstack-integration-test::setup'

edit_resource(:python_virtualenv, '/opt/tempest-venv') do
  system_site_packages true
  pip_version '9.0.3'
end
