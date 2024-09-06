source ./env.sh
# vpc_id=$(aws eks describe-cluster --name $AWS_EKS_CLUSTER --query "cluster.resourcesVpcConfig.vpcId" --output text)

echo "VPC_ID : $AWS_VPC_ID"
echo "EKS_CLUSTER_ID : $AWS_EKS_CLUSTER"
echo "AWS_REGION : $AWS_REGION"
echo "AWS_SG_KF_NAME: ${AWS_SG_KF_NAME}"


cidr_range=$(aws ec2 describe-vpcs \
--vpc-ids $AWS_VPC_ID \
--query "Vpcs[].CidrBlock" \
--output text \
--region $AWS_REGION)

echo "cidr_range: ${cidr_range}"

# 존재 하면 기존 내용 사용
existing_sg_id=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${AWS_SG_KF_NAME}" "Name=vpc-id,Values=${AWS_VPC_ID}" --query "SecurityGroups[0].GroupId" --output text)


if [ "$existing_sg_id" != "None" ]; then
    echo "Using existing security group: $existing_sg_id"
    AWS_SG_KF_ID=$existing_sg_id
else
    echo "Security group not found. Creating a new one..."
    AWS_SG_KF_ID=$(aws ec2 create-security-group \
        --group-name $AWS_SG_KF_NAME \
        --description "kubeflow efs security group" \
        --vpc-id $AWS_VPC_ID \
        --output text)
    echo "Created new security group: $AWS_SG_KF_ID"
fi

echo "security_group_id: ${AWS_SG_KF_ID}"

aws ec2 authorize-security-group-ingress \
    --group-id $AWS_SG_KF_ID \
    --protocol tcp \
    --port 2049 \
    --cidr $cidr_range

echo "authorize-security-group-ingress: ${AWS_SG_KF_ID} ${cidr_range}"


if [ -z "$AWS_EFS_FS_ID" ]; then
    echo "No file system ID provided. Creating a new EFS file system..."

    # 새로운 EFS 파일 시스템 생성
    AWS_EFS_FS_ID=$(aws efs create-file-system \
        --creation-token "my-efs-$(date +%s)" \
        --query "FileSystemId" \
        --output text)
    
    echo "Created new EFS file system with ID: $AWS_EFS_FS_ID"
else
    echo "Using provided file system ID: $AWS_EFS_FS_ID"
fi

subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${AWS_VPC_ID}" --query "Subnets[*].SubnetId" --output text)
echo "subnets : ${subnets}"

for subnet_id in $subnets; do
    echo "Creating mount target for subnet $subnet_id..."

    aws efs create-mount-target \
        --file-system-id $AWS_EFS_FS_ID \
        --subnet-id $subnet_id \
        --security-groups $AWS_SG_KF_ID

    echo "Mount target created for subnet $subnet_id"
done
