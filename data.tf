## Uncomment this data_source when destroy the cluster
# data "aws_eks_cluster" "this" {
#   name  = var.eks_cluster_name
# }

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}