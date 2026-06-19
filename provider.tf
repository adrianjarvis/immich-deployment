terraform {
  required_version = ">= 1.2"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.1.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.3"
    }
  }
}

