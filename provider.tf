terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
      version = "~> 1.0"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
