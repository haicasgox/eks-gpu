terraform {
  required_version = " ~> 1.10.3"

  backend "s3" {
    bucket         = "your-s3-bucket"
    key            = "eks/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "your-dynamodb-table"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82.2"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20.0"
    }

    helm = {
      source = "hashicorp/helm"
      version = "2.17.0"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}
