# private-eks-cluster

This repository is a collection of CloudFormation templates and shell scripts to create an Amazon EKS Kubernetes cluster in an AWS Virtual Private Cloud (VPC) without any Internet connectivity.

## Overview

This collection of CloudFormation templates and Bash shell scripts will deploy an EKS cluster into a VPC with no Internet Gateway (IGW) or NAT Gateway attached.

To do this it will create:
- VPC
- VPC endpoints - for EC2, ECR, STS, AutoScaling, SSM
- VPC endpoint for Proxy (optional) - to an existing web proxy that you have already setup (not required by EKS but assumed you want to pull containers from DockerHub, GCR.io etc)
- IAM Permissions
- EKS Cluster - logging enabled, encrypted secrets, no public endpoint
- OIDC IDP - To allow pods to assume AWS roles
- Auto-scaling Group for Node group (optional) - including optional bootstrap configuration for the proxy
- Fargate Profile (optional) - for running containers on Fargate

Once completed you can (from within the VPC) communicate with your EKS cluster and see a list of running worker nodes.

## Quickstart

1. Clone this repository to a machine that has CLI access to your AWS account.
2. Edit the values in `variables.sh`

    1. Set `CLUSTER_NAME` to be a name you choose
    2. Set `REGION` to be an AWS region you prefer, such as us-east-2, eu-west-2, or eu-central-1
    3. Edit `AMI_ID` to be correct for your region
    4. Ensure you have the right Kubernetes version set by updating `VERSION`
    5. Edit/Update `PRIVATE_VPC_CIDR` of your choice
    6. Edit/Update `PRIVATE_SUBNET1_CIDR` of your choice
    7. Edit/Update `PRIVATE_SUBNET2_CIDR` of your choice
    8. Edit/Update `PRIVATE_SUBNET3_CIDR` of your choice
   
3. Execute `launch_all.sh`

## Getting started

Edit the variable definitions found in `variables.sh`.

These variables are:
 - CLUSTER_NAME - your desired EKS cluster name
 - REGION - the AWS region in which you want the resources created
 - HTTP_PROXY_ENDPOINT_SERVICE_NAME - this is the name of a VPC endpoint service you must have previously created which represents an HTTP proxy (e.g. Squid)
 - KEY_PAIR - the name of an existing EC2 key pair to be used as an SSH key on the worker nodes
 - VERSION - the EKS version you wish to create ('1.16', '1.15', '1.14' etc)
 - AMI_ID - the region-specific AWS EKS worker AMI to use. (See here for the list of managed AMIs)[https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html]
 - INSTANCE_TYPE - the instance type to be used for the worker nodes
 - S3_STAGING_LOCATION - an existing S3 bucket name and optional prefix to which CloudFormation templates and a kubectl binary will be uploaded
 ### Not Tested
 - ENABLE_FARGATE - set to 'true' to enable fargate support, disabled by default as this requires the proxy to be a transparent proxy 
 - FARGATE_PROFILE_NAME - the name for the Fargate profile for running EKS pods on Fargate
 - FARGATE_NAMESPACE - the namespace to match pods to for running EKS pods on Fargate. You must also create this inside the cluster with 'kubectl create namespace fargate' and then launch the pod into that namespace for Fargate to be the target

If you do not have a proxy already configured you can use the cloudformation/proxy.yaml template provided which is a modified version of the template from this guide:
https://aws.amazon.com/blogs/security/how-to-add-dns-filtering-to-your-nat-instance-with-squid/
This will setup a squid proxy in it's own VPC that you can use, along with a VPC endpoint service and test instance. The template can take a parameter: "whitelistedDomains" - a list of whitelisted domains separated by a comma for the proxy whitelist. This is refreshed on a regular basis, so modifying directly on the EC2 instance is not advised.
```
aws cloudformation create-stack --stack-name filtering-proxy --template-body file://cloudformation/proxy.yaml --capabilities CAPABILITY_IAM
export ACCOUNT_ID=$(aws sts get-caller-identity --output json | jq -r '.Account')
export HTTP_PROXY_ENDPOINT_SERVICE_NAME=$(aws ec2 describe-vpc-endpoint-services --output json | jq -r '.ServiceDetails[] | select(.Owner==env.ACCOUNT_ID) | .ServiceName')
echo $HTTP_PROXY_ENDPOINT_SERVICE_NAME
```
After, enter the output of the proxy endpoint service name into the `variables.sh` file.

 Once these values are set you can execute `launch_all.sh` and get a coffee. This will take approximately 10 - 15 min to create the vpc, endpoints, cluster, and worker nodes.

 After this is completed you will have an EKS cluster that you can review using the AWS console or CLI. You can also remotely access your VPC using an Amazon WorkSpaces, VPN, or similar means. Using the `kubectl` client you should then see something similar to:

```
[ec2-user@ip ~]$ kubectl get nodes
NAME                                          STATUS   ROLES    AGE   VERSION
ip-10-0-2-186.eu-central-1.compute.internal   Ready    <none>   45m   v1.13.8-eks-cd3eb0
ip-10-0-4-219.eu-central-1.compute.internal   Ready    <none>   45m   v1.13.8-eks-cd3eb0

[ec2-user@ip ~]$ kubectl get ds -n kube-system
NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
aws-node     3         3         3       3            3           <none>          52m
kube-proxy   3         3         3       3            3           <none>          52m
```

**There you go - you now have an EKS cluster in a private VPC!**

## Code Explained

`variables.sh` defines key user configurable values that control how the scripts exxecute to create an EKS cluster.  These values control whether Fargate is used to host worker nodes, whether a proxy server is configured on the worker nodes, and whether you would like the EKS master node to be accessible from outside of the VPC.  

`launch_all.sh` sources the values from `variables.sh` and then begins by creating an S3 bucket (if it does not already exist) to host the CloudFormation templates and kubectl binary.  With an S3 bucket in place the script then moves on to deploying the CloudFormation stack defined by `environment.yaml`.  This stack deploys 2 nested stacks, `permissions.yaml` and `network.yaml`.  

`permissions.yaml` creates an IAM role for the EKS cluster, a KMS key to encrypt K8s secrets held on the EKS master node, and an IAM role for the EC2 worker nodes to be created later.

`network.yaml` creates a VPC with no IGW and 3 subnets.  It also creates VPC endpoints for Amazon S3, Amazon ECR, Amazon EC2, EC2 AutoScaling, CloudWatch Logs, STS, and SSM.  If an VPC endpoint service is specified for a proxy server an VPC Endpoint will also be created to point at the proxy server.  

With permissions and a network in place the `launch_all.sh` script next launches an EKS cluster using the AWS CLI.  This cluster will be configured to operate privately, with full logging to CloudWatch logs, Kubernetes secrets encrypted using a KMS key, and with the role created in the `permissions.yaml` CloudFormation template.  The script will then pause while it waits for the cluster to finish creating.

Next the script will configured an OpenID Connect Provider which will be used to allow Kubernetes pods to authenticate against AWS IAM and obtain temporary credentials.  This works in a manner similar to EC2 instance profiles where containers in the pod can then reference AWS credentials as secrets using standard K8s parlance.

After the EKS cluster has been created an the OIDC provider configured the script will then configure your local `kubectl` tool to communicate with the EKS cluster.  Please note this will only work if you have a network path to your EKS master node.  To have this network path you will need to be connected to your VPC over Direct Connect or VPN, or you will have to enable communication with your EKS master node from outside of the VPC.

Next the script will hand control over to `launch_workers.sh` which will again read values from `variables.sh` before proceeding.

`launch_workers.sh` will read values from the previous CloudFormation stack to know what VPC subnets and security groups to use.  The script will retreive the HTTPS endpoint for the EKS master node, and the CA certificate to be used during communication with the master.  It will also request a token for communicating with the EKS master node created by `launch_all.sh`.  

With these values in hand the script will then launch worker nodes to run your K8s pods.  Depending on your configuration of `variables.sh` the script will either apply the `fargate.yaml` CloudFormation template and create a Fargate Profile with EKS, allowing you to run a fully serverless K8s cluster.  Or it will create an EC2 autoscaling group to create EC2 instances in your VPC that will connect with the EKS master node.

To create the EC2 instances the script will first download the `kubectl` binary and store it in S3 for later retreival by the worker nodes.  It will then apply the `eks-workers.yaml` CloudFormation template.  The template will create a launch configuration and autoscaling group that will create EC2 instances to host your pods.

When they first launch the EC2 worker nodes will use the CA certificate and EKS token provided to them to configure themselves and communicate with the EKS master node.  The worker nodes, using Cloud-Init user data, will apply an auth config map to the EKS master node, giving the worker nodes permission to register as worker nodes with the EKS master.  If a proxy has been configured the EC2 instance will configure Docker and Kubelet to use your HTTP proxy.  The EC2 instance will also execute the EKS bootstrap.sh script which is provided by the EKS service AMI to configure the EKS components on the system.  Lastly the EC2 instance will insert an IPTables rule that disallows pods to query the EC2 metadata service.

When the CloudFormation template has been applied and the user data has executed on the EC2 worker nodes the shell script will return and you should now have a fully formed EKS cluster running privately in a VPC.

## Delete Everything
1. Ensure the values in `variables.sh` are correct
2. Execute `delete_all.sh`

## Managing the cluster
1. You can create a bastion instance in any one of the Private subnets.
2. Use the ami-id `ami-0ce29f1698cab2968` for creation, this ami consists of tools through which you can manage EKS.
3. Ensure that you attach the IAM role `role-eks-bastion` while creating the instance.
4. Select an existing security group that contains the name **EndpointSecurityGroup**
5. Once the instance is ready, connect to the instance using SSM.
6. Execute the below commands to export the below variables:
```
export CLUSTER_NAME=eks-test-01
export REGION=us-east-2
```
6. Create a new file `assume_role.sh` with below contents, this will be used to assume the role `role-terraform-global`:
```
REGION=$REGION
ROLE=arn:aws:iam::948659541789:role/role-global-terraform
echo "===== assuming permissions => $ROLE ====="
KST=(`aws sts assume-role --role-arn $ROLE --role-session-name "ClusterDeploy" --query '[Credentials.AccessKeyId,Credentials.SecretAccessKey,Credentials.SessionToken]' --output text`)
unset AWS_SECURITY_TOKEN
export AWS_DEFAULT_REGION=$REGION
export AWS_ACCESS_KEY_ID=${KST[0]}
export AWS_SECRET_ACCESS_KEY=${KST[1]}
export AWS_SESSION_TOKEN=${KST[2]}
export AWS_SECURITY_TOKEN=${KST[2]}
```
7. Download the kubeconfig file created by our script stored as a SecureString in the parameter store by running the following commands:
```
mkdir /root/.kube
aws --region=$REGION ssm get-parameter --name "/infra/EKS_KUBECONFIG" --with-decryption --output text --query Parameter.Value > /root/.kube/config
chmod 400 /root/.kube/config   
```
