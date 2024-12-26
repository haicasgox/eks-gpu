## About

This repository shows how to run Nvidia GPU-based workloads on Amazon EKS. Recently, AWS introduced [EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html), a feature designed to simplify cluster management and reduce administrative overhead. While I attempted to use EKS Auto Mode for this deployment, I encountered limitations with worker node scaling configurations. Therefore, this repository demonstrates deploying GPU workloads on a manually provisioned and managed EKS cluster instead.

## Prerequisites
The list of prerequisites for running this deployment is described below:

- Terraform ~> 1.10.3
- aws-cli version 2

## Quick Start
### Preparing your EKS Cluster

1. Create your Terraform backend to store the state:
```shell
cd backend
terraform init
terraform plan 
terraform apply
```
Copy Terraform outputs, go to version.tf file and then replace 'your-s3-bucket' and 'your-dynamodb-table' by those outputs.

2. Reconfigure Terraform backend and create EKS cluster

Reconfigure Terraform backend
```shell
cd ..
terraform init --reconfigure
```

Create EKS cluster
```shell
terraform plan
terraform apply
```

Then, make sure you have an available EKS cluster. In the cluster, you will have running Karpenter controller pods.

### Configure Karpenter to scale GPU-enabled worker nodes
In case you want to scale both general worker nodes and GPU-enabled worker nodes, you will have the corresponding EC2NodeClass and Nodepool:

- For general worker nodes:
```shell
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["c", "m", "r"]
        - key: "karpenter.k8s.aws/instance-cpu"
          operator: In
          values: ["4", "8", "16", "32"]
        - key: "karpenter.k8s.aws/instance-hypervisor"
          operator: In
          values: ["nitro"]
        - key: "karpenter.k8s.aws/instance-generation"
          operator: Gt
          values: ["2"]
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
```
- For GPU-enabled worker nodes:
```shell
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: nvdia-gpu
spec:
  template:
    metadata:
      labels:
        nvidia.com/gpu.present: "true"
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: gpu

      requirements:
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["g"]
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["g4dn", "g5"]
        - key: karpenter.k8s.aws/instance-size
          operator: In
          values: ["2xlarge", "4xlarge", "8xlarge"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["on-demand", "spot"]
        - key: "karpenter.k8s.aws/instance-hypervisor"
          operator: In
          values: ["nitro"]
      taints:
        - key: nvidia.com/gpu
          effect: NoSchedule
  limits:
    cpu: "80"
    memory: 128Gi

```
Karpenter manages the scaling of workder nodes. Worker nodes equiped with Nvidia GPU have a taint with the key `nvidia.com/gpu` and label `nvidia.com/gpu.present: "true"`. Only pods that are configured to tolerate this GPU taint will be scheduled to run on these GPU-enabled worker nodes.
Note: You need to check the accelerated EC2 instances availability in AWS region in which you are deploying.

### Install and configure Nvidia device plugin
In order to deploy GPU-based workload on EKS cluster, you need to install plugin. In this case, you will deploy Nvidia device plugin. The NVIDIA device plugin for Kubernetes is a Daemonset that allows you to automatically:

- Expose the number of GPUs on each nodes of your cluster
- Keep track of the health of your GPUs
- Run GPU enabled containers in your Kubernetes cluster.

There are some ways to install the plugin. Refer to [this repository](https://github.com/NVIDIA/k8s-device-plugin) for your reference.

Begin by setting up the plugin's helm repository and updating it at follows:
```shell
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update

```
Then verify that the latest release (v0.17.0) of the plugin is available:
```shell
 helm search repo nvdp --devel
NAME                            CHART VERSION   APP VERSION     DESCRIPTION                                       
nvdp/gpu-feature-discovery      0.17.0          0.17.0          A Helm chart for gpu-feature-discovery on Kuber...
nvdp/nvidia-device-plugin       0.17.0          0.17.0          A Helm chart for the nvidia-device-plugin on Ku...
```
Once this repo is updated, you can begin installing packages from it to deploy the nvidia-device-plugin helm chart.
```shell
helm upgrade -i nvdp nvdp/nvidia-device-plugin --namespace nvidia-device-plugin \
 --create-namespace --version 0.17.0 -f $PWD/nvidia-device-plugin/timeslicing.yaml
```
Note: Nvidia GPU time-slicing in Kubernetes allows tasks to share a GPU by taking turns. This feature enables multiple tasks to share a single GPU by allocating time slots to each task. Instead of dedicating an entire GPU to a single task, time-slicing allows the GPU to switch between different tasks. It is very useful for scenarios where workloads do not need continuous GPU access.
```shell
config:
  # ConfigMap name if pulling from an external ConfigMap
  name: ""
  # Set of named configs to build an integrated ConfigMap from
  map:
    default: |-
        version: v1
        flags:
          migStrategy: "none"
          failOnInitError: true
          nvidiaDriverRoot: "/"
          plugin:
            passDeviceSpecs: false
            deviceListStrategy: ["envvar"]
            deviceIDStrategy: "uuid"
        sharing:
          timeSlicing:
            renameByDefault: false
            resources:
            - name: nvidia.com/gpu
              replicas: 10  ##Replicas will split physical GPU into 10 virtual GPUs through time-slicing. 
```

### Deploy sample GPU-based workload
Run command to deploy workload:
```shell
kubectl apply -f sample-workload/deployment.yaml
```
```shell
kind: Deployment
apiVersion: apps/v1
metadata:
  name: gpu
  labels:
    app: gpu
spec:
  replicas: 2
  selector:
    matchLabels:
      app: gpu
  template:
    metadata:
      labels:
        app: gpu
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      containers:
      - name: gpu-container
        image: tensorflow/tensorflow:latest-gpu
        imagePullPolicy: Always
        command: ["sleep","infinity"]
        resources:
          limits:
            nvidia.com/gpu: 1
```

The deployment creates 02 pods with GPU capabilities, each running the TensorFlow GPU-enabled container image. By requesting 01 GPU per pod and including `nvidia.com/gpu` toleration, these pods are specifically scheduled to run on worker nodes equipped with GPUs.

Karpenter scaled out GPU-enabled worker node:
```shell
{"level":"INFO","time":"2024-12-26T08:12:58.157Z","logger":"controller","message":"registered nodeclaim","commit":"3298d91","controller":"nodeclaim.lifecycle","controllerGroup":"karpenter.sh","controllerKind":"NodeClaim","NodeClaim":{"name":"nvdia-gpu-tt4wc"},"namespace":"","name":"nvdia-gpu-tt4wc","reconcileID":"077407e9-84e4-4abc-969d-7cad8a81451a","provider-id":"aws:///ap-southeast-1c/i-0606471494b620009","Node":{"name":"ip-10-0-37-13.ap-southeast-1.compute.internal"}}
{"level":"INFO","time":"2024-12-26T08:13:15.724Z","logger":"controller","message":"initialized nodeclaim","commit":"3298d91","controller":"nodeclaim.lifecycle","controllerGroup":"karpenter.sh","controllerKind":"NodeClaim","NodeClaim":{"name":"nvdia-gpu-kmn9m"},"namespace":"","name":"nvdia-gpu-kmn9m","reconcileID":"3381f68a-e805-4a6d-98f7-d7bdb0574263","provider-id":"aws:///ap-southeast-1a/i-091390808f0c9d0c4","Node":{"name":"ip-10-0-15-155.ap-southeast-1.compute.internal"},"allocatable":{"cpu":"7910m","ephemeral-storage":"18181869946","hugepages-1Gi":"0","hugepages-2Mi":"0","memory":"31785232Ki","nvidia.com/gpu":"10","pods":"29"}}
```

With 10 replicas of time-slicing in above configuration, Nvidia device plugin daemonset advertises 10 virtual GPUs on this node to EKS cluster:

```shell
kubectl get nodes
kubectl describe node ip-10-0-15-155.ap-southeast-1.compute.internal | grep -A 8 'Capacity:\|Allocatable:'
```

```sh
Capacity:
  cpu:                8
  ephemeral-storage:  20893676Ki
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             32475408Ki
  nvidia.com/gpu:     10
  pods:               29
Allocatable:
  cpu:                7910m
  ephemeral-storage:  18181869946
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             31785232Ki
  nvidia.com/gpu:     10
  pods:               29
System Info:
```