#!/usr/bin/env bash

CLUSTER_NAME='eks-test-01'
REGION=us-east-2
HTTP_PROXY_ENDPOINT_SERVICE_NAME="" # leave blank for no proxy, or populate with a VPC endpoint ID to create a PrivateLink powered connection to a proxy server
KEY_PAIR=""
VERSION='1.22' # K8s version to deploy
PRIVATE_VPC_CIDR="10.241.176.0/20"
PRIVATE_SUBNET1_CIDR="10.241.185.0/24"
PRIVATE_SUBNET2_CIDR="10.241.187.0/24"
PRIVATE_SUBNET3_CIDR="10.241.189.0/24"
AMI_ID=ami-0228214e1a9fc610f # AWS managed AMI for EKS worker nodes
INSTANCE_TYPE=t3.medium # instance type for EKS worker nodes
S3_STAGING_LOCATION=s3-abc-us-east-2 # S3 location to be created to store Cloudformation templates and a copy of the kubectl binary
ENABLE_PUBLIC_ACCESS=false
ENABLE_FARGATE=false
FARGATE_PROFILE_NAME=PrivateFargateProfile
FARGATE_NAMESPACE=fargate
