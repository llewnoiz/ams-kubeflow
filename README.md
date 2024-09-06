# KUBEFLOW 1.9 버전을 설치 문서
```
AWS EKS 상에 Kubeflow 1.9 버전을 설치하기 위한 가이드 라인과 설정을 제공한다.

가이드라인 순서를 1번 부터 따라하면서 kubeflow 설치가 가능하다.

*(옵션)이라고 되어있는 표시는 적용해서 사용해도 되고 적용하지 않아도 동작상 문제는 없다.
```

# DIR
```
├── README.md                    kubeflow 설치에 대한 설명
├── scripts                      kubeflow 설치 스크립트
├── iam                          kubeflow 설치에 필요한 iam 정책 폴더
│   └── alb_iam_policy.json
├── manifests                    kubeflow manifests 폴더
│   ├── LICENSE
│   ├── OWNERS
│   ├── README.md
│   ├── apps
│   ├── common
│   ├── contrib
│   ├── example
│   ├── hack
│   ├── proposals
│   ├── run_yamllint.sh
│   └── tests
└── yaml                         kubeflow manifests 추가/변경 기능 관련한 yaml 폴더
    └── kubeflow-ingress.yaml
    └── aws-efs.yaml
```
# 수동 설치 1 - 11
## 1. eks ctl 설치

```

curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp

sudo mv /tmp/eksctl /usr/local/bin

eksctl version

- 0.188.0

```

## 2. kubectl 설치

```

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

chmod +x kubectl
mkdir -p ~/.local/bin
mv ./kubectl ~/.local/bin/kubectl
# and then append (or prepend) ~/.local/bin to $PATH

kubectl version --client

```

## 3. aws 설정

```

aws configure --profile=kubeflow
aws sts get-caller-identity

```

## 4. kustomize 설치

```

curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/

```

## 5.환경 설정
```

export AWS_REGION=AWS 리전 정보
export AWS_EKS_CLUSTER=EK 클러스터 이름
export AWS_ACCOUNT_ID=AWS 계정 정보
export AWS_VPC_ID=AWS VPC ID

```


## 6. EKS 클러스터 배포

```

설치
eksctl create cluster --name $AWS_EKS_CLUSTER --version 1.29 --region $AWS_REGION --nodegroup-name linux-nodes --node-type c4.large --nodes 5 --nodes-min 5 --nodes-max 10 --managed --with-oidc
eksctl utils associate-iam-oidc-provider --cluster $AWS_EKS_CLUSTER --region $AWS_REGION --approve


정보
kubectl config current-context
aws eks describe-cluster --name $AWS_EKS_CLUSTER --region $AWS_REGION

aws eks update-kubeconfig --region $AWS_REGION --name $AWS_EKS_CLUSTER

삭제 시
eksctl delete cluster --name=$AWS_EKS_CLUSTER

```

## 7. kubeflow 소스

```

git clone https://github.com/kubeflow/manifests.git
cd manifests
git checkout v1.9-branch

```

## 8. kubeflow 설치
: manifests 폴더에서 설치 진행

```

while ! kustomize build example | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done

```

## 9. 설치 pods 확인

```

kubectl get pods -n cert-manager
kubectl get pods -n istio-system
kubectl get pods -n auth
kubectl get pods -n knative-eventing
kubectl get pods -n knative-serving
kubectl get pods -n kubeflow
kubectl get pods -n kubeflow-user-example-com

```

## 10. 접속 확인

```
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
user@example.com / 12341234

```

## 11. EBS
```
IRSA 생성

eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $AWS_EKS_CLUSTER \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --role-only \
  --role-name AmazonEKS_EBS_CSI_DriverRole

IRSA 확인
eksctl get iamserviceaccount --cluster $AWS_EKS_CLUSTER

설치
eksctl create addon --name aws-ebs-csi-driver\
 --cluster ${CLUSTER_NAME}\
 --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole\
 --force

확인
eksctl get addon --cluster $AWS_EKS_CLUSTER

```

## 11. EFS (옵션)
```
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/docs/iam-policy-example.json


aws iam create-policy \
--policy-name AmazonEKS_EFS_CSI_Driver_Policy \
--policy-document file://iam-policy-example.json

IRSA 생성
eksctl create iamserviceaccount \
    --cluster $AWS_EKS_CLUSTER \
    --namespace kube-system \
    --name efs-csi-controller-sa \
    --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AmazonEKS_EFS_CSI_Driver_Policy \
    --approve \
    --region $AWS_REGION


IRSA 확인
eksctl get iamserviceaccount --cluster $AWS_EKS_CLUSTER

설치
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/

helm repo update
helm install aws-efs-csi-driver/aws-efs-csi-driver \
  --name-template efs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=efs-csi-controller-sa \
  --set region=$AWS_REGION

kubectl get pod -n kube-system -l "app.kubernetes.io/name=aws-efs-csi-driver,app.kubernetes.io/instance=efs-csi-driver"

EFS 생성 
./scripts/env.sh 에 관련 값 설정 필요
./scripts/create-efs.sh


kubectl apply -f ./yaml/aws-efs.yaml
```

##  11. ALB 연결 (옵션)

```

curl -o alb_iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://alb_iam_policy.json
  
eksctl utils associate-iam-oidc-provider --region $AWS_REGION --cluster $AWS_EKS_CLUSTER --approve

eksctl create iamserviceaccount \
  --cluster $AWS_EKS_CLUSTER \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
  
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$AWS_EKS_CLUSTER \
  --set serviceAccount.create=false \
  --set region=$AWS_REGION \
  --set vpcId=$AWS_VPC_ID \
  --set serviceAccount.name=aws-load-balancer-controller

```
## 11. INGRESS 설정 (옵션) - ALB 연결시 사용
host 정보 설정 필요
```
 kubectl apply -f ./yaml/kubeflow-ingress.yaml
```

## 참고
```
https://github.com/kubeflow/manifests/tree/v1.9-branch#installation
https://kschoi728.tistory.com/94 
```