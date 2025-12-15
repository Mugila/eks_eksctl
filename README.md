# eks_eksctl


create only service account from existing config file 
eksctl create iamserviceaccount -f  cluster_creation.yaml  --approve 
eksctl delete   cluster -f cluster_creation.yaml 
eksctl create  cluster -f cluster_creation.yaml  --timeout=45m  --verbose 4

https://medium.com/@muppedaanvesh/a-hands-on-guide-to-aws-eks-iam-roles-for-service-accounts-irsa-%EF%B8%8F-558c7a3e7c69
https://aws.plainenglish.io/eks-pod-identity-the-sres-guide-for-secure-iam-dc12633213ec

https://pumasecurity.io/resources/blog/auditing-eks-pod-permissions/
https://www.digihunch.com/2024/01/workload-identity-on-kubernetes-2-of-2-eks-and-rosa-on-aws/

https://github.com/anveshmuppeda/kubernetes.  ###hands on Guide#############

https://medium.com/@muppedaanvesh/a-hands-on-guide-to-aws-eks-iam-roles-for-service-accounts-irsa-%EF%B8%8F-558c7a3e7c69  ## steps to create IRSA using AWS cli ,eksctl and cloudformation ###
https://docs.aws.amazon.com/eks/latest/eksctl/pod-identity-associations.html
https://www.eksworkshop.com/docs/security/amazon-eks-pod-identity/use-pod-identity
https://repost.aws/knowledge-center/eks-troubleshoot-oidc-and-irsa