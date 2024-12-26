provider "aws" {
  region = "ap-southeast-1"
  alias  = "singapore"
  default_tags {
    tags = {
      environment = "dev"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

## Comment these providers when destroy the cluster, vice versa
provider "kubernetes" {
  host                   = module.eks.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.eks_cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}
