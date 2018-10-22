#!/bin/sh
# This is only an example based on
# https://github.com/knative/docs/blob/master/install/Knative-with-Minikube.md
# and
# https://github.com/kubernetes/minikube/issues/2162#issuecomment-354392686

set -e

minikube version | grep v0.28 && echo "You might need extra args for <0.29 minikube, see https://github.com/istio/istio.io/pull/2708"

minikube start --memory=8192 --cpus=4 \
  --kubernetes-version=v1.11.3 \
  --vm-driver=hyperkit \
  --bootstrapper=kubeadm \
  --extra-config=apiserver.enable-admission-plugins="LimitRanger,NamespaceExists,NamespaceLifecycle,ResourceQuota,ServiceAccount,DefaultStorageClass,MutatingAdmissionWebhook"

# --insecure-registry 10.0.0.0/24 should not be needed because according to docs "The default service CIDR range will automatically be added"

minikube addons list | grep -E "coredns|kube-dns"

echo "Updating minikube DNS resolution, see github.com/kubernetes/minikube/issues/2162"
kubectl get svc kube-dns -n kube-system
DNS_IP=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}')
echo "kube-dns IP is $DNS_IP"

echo "Updating name resolution ..."
# Commented out the resolv.conf change because of presumable side effects as it's propagated to k8s
#ssh -i $(minikube ssh-key) -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no docker@$(minikube ip) \
#  "sudo sed -i 's/^nameserver/nameserver $DNS_IP\nnameserver/' /etc/resolv.conf"
# Someone who knows DNS and/or minikube, can we resolve all .local using k8s elegantly?
# https://forums.docker.com/t/docker-pull-not-using-correct-dns-server-when-private-registry-on-vpn/11117/11
# https://github.com/kubernetes/minikube/issues/1165
# For now simply adding the known service name to /etc/hosts
kubectl create namespace registry
kubectl apply -f templates/registry-service-knative.yaml
REGISTRY_IP=$(kubectl get svc knative -n registry -o jsonpath='{.spec.clusterIP}')
ssh -i $(minikube ssh-key) -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no docker@$(minikube ip) \
  "echo '$REGISTRY_IP knative.registry.svc.cluster.local' | sudo tee -a /etc/hosts"

kubectl apply -f templates/registry-cert-authz.yaml
kubectl apply -f templates/registry-cert-job.yaml
until kubectl certificate approve registry-tls 2>/dev/null;
do
  echo "Waiting for registry cert job to request a certificate ..."
  sleep 1
done

echo "Starting registry ..."
kubectl apply -f templates/

### Would you like to install Knative using github.com/triggermesh/charts?
kubectl cluster-info
# TODO can we run this in k8s instead, to avoid dependence on local Helm?
#helm init
#helm repo add tm https://storage.googleapis.com/triggermesh-charts
#helm repo update
#helm search knative
#helm install tm/knative
#kubectl get pods --all-namespaces -w
