1 apply ns-secret

kubectl --namespace kasten-io apply -f \
  https://raw.githubusercontent.com/kanisterio/kanister/0.113.0/examples/etcd/etcd-in-cluster/k8s/etcd-incluster-blueprint.yaml