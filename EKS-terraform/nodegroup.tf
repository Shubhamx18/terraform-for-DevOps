module "nodes" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"

  cluster_name    = module.eks.cluster_name
  cluster_version = module.eks.cluster_version

  node_group_name = "practice-nodes"
  subnet_ids      = module.vpc.private_subnets

  instance_types = ["t3.medium"]

  min_size     = 1
  max_size     = 2
  desired_size = 1

  capacity_type = "ON_DEMAND"

  disk_size = 20
  ami_type  = "AL2_x86_64"

  tags = {
    Environment = var.environment
  }
}
