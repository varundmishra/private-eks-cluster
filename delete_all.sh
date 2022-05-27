#!/usr/bin/env bash
set -e

source variables.sh 

# Delete any bastion/eks management instances created in the Private Subnets before running this script

# Deleting the Worker Node Stack
if aws cloudformation describe-stacks --region ${REGION} --stack-name cf-${CLUSTER_NAME}-worker ; then
  aws cloudformation delete-stack --stack-name cf-${CLUSTER_NAME}-worker --region ${REGION}
  aws cloudformation wait stack-delete-complete --region ${REGION} --stack-name cf-${CLUSTER_NAME}-worker
else
  echo "Error: Unable to delete cf-${CLUSTER_NAME}-worker stack. Stack already deleted or does not exist"
fi

# Deleting the EKS Cluster
export CLUSTER_CHECK=$(aws eks list-clusters | jq -r ".clusters" | grep ${CLUSTER_NAME} || true)
if [ "$CLUSTER_CHECK" != "" ]; then
    echo "EKS Cluster Exists...Deleting the  Cluster..."
    eksctl delete cluster --name=${CLUSTER_NAME} --region ${REGION}
#    eksctl utils update-cluster-endpoints --cluster=${CLUSTER_NAME} --private-access=true --region ${REGION} --public-access=true --approve
#    aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}
#    helm delete aws-load-balancer-controller -n kube-system
#    helm delete cluster-autoscaler -n kube-system
#    helm delete metrics-server -n kube-system
#    eksctl delete iamserviceaccount --cluster=${CLUSTER_NAME} --region=${REGION} --namespace=kube-system --name=aws-load-balancer-controller
#    eksctl delete iamserviceaccount --cluster=${CLUSTER_NAME} --region=${REGION} --namespace=kube-system --name=cluster-autoscaler            
else
    echo "No cluster by this name ${CLUSTER_NAME}, will continue with terraform destroy..."
fi

# Deleting the Master Stack
if aws cloudformation describe-stacks --region ${REGION} --stack-name cf-${CLUSTER_NAME}-vpc ; then
  aws cloudformation delete-stack --stack-name cf-${CLUSTER_NAME}-vpc --region ${REGION}
  aws cloudformation wait stack-delete-complete --region ${REGION} --stack-name cf-${CLUSTER_NAME}-vpc
else
  echo "Error: Unable to delete cf-${CLUSTER_NAME}-vpc stack. Stack already deleted or does not exist"
fi
