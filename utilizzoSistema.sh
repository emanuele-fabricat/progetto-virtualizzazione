#!/bin/bash

#Utilizzo sistema
minikube kubectl -- port-forward -n progetto svc/traefik 8081:80


#script per reperire yaml
mkdir ./progetto-virtualizzazione/YamlDebian

for kind in deployments statefulsets services; do
  for name in $(minikube kubectl -- get "$kind" -n progetto -o jsonpath='{.items[*].metadata.name}'); do
    minikube kubectl -- get "$kind" "$name" -n progetto -o yaml \
      > "./progetto-virtualizzazione/YamlDebian/${kind}-${name}.yaml"
  done
done


mkdir ./progetto-virtualizzazione/YamlUbuntu

for kind in deployments statefulsets services; do
  for name in $(minikube kubectl -- get "$kind" -n progetto -o jsonpath='{.items[*].metadata.name}'); do
    minikube kubectl -- get "$kind" "$name" -n progetto -o yaml \
      > "./progetto-virtualizzazione/YamlUbuntu/${kind}-${name}.yaml"
  done
done
