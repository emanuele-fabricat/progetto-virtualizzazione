#!/bin/bash
#Installazione Docker 
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

#Installazione minikube per linux tramite binary download
url -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64

#Avviare minikube
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
sudo systemctl enable --now docker

# Esegui lo script come utente normale, non con "sudo ./scriptPrincipale.sh"
sudo usermod -aG docker "$USER"

# sg avvia questi comandi con il gruppo docker attivo, senza logout/login
sg docker -c '
  set -e
  minikube config set driver docker
  minikube start --driver=docker
  minikube status
  minikube kubectl -- get nodes
'

#Installazione helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh

#Creazione del namespace progetto dov’è saranno messi tutti i servizi tranne linkerd
minikube kubectl -- create namespace progetto


#Installazione bitnami
helm repo add bitnami https://charts.bitnami.com/bitnami

#Installazione apache
helm install mio-apache oci://registry-1.docker.io/bitnamicharts/apache \
  -n progetto \
  --set service.type=ClusterIP \
  --set image.repository=bitnamilegacy/apache \
  --set image.tag=latest

#Installazione mariaDB
helm install mio-mariadb bitnami/mariadb \
  -n progetto \
  --set auth.rootPassword=Admin1234! \
  --set image.repository=bitnamilegacy/mariadb \
  --set global.security.allowInsecureImages=true \
  --set auth.database=miodb \
  --set auth.username=adimn \
  --set auth.password=Admin1234!

#Installazione keycloak con postgress
helm install mio-keycloak bitnami/keycloak \
  -n progetto \
  --set auth.adminUser=admin \
  --set auth.adminPassword=Admin1234! \
  --set postgresql.auth.postgresPassword=Admin1234! \
  --set postgresql.auth.username=admin \
  --set postgresql.auth.password=Admin1234! \
  --set postgresql.auth.database=keycloak_db


#Installazione traefik
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik \
  -n progetto

#Installazione Oauth2-proxy
helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
helm repo update
helm upgrade --install oauth2-proxy oauth2-proxy/oauth2-proxy \
  -n progetto


minikube kubectl -- apply -f - <<'YAML'
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: oauth2-forwardauth
  namespace: progetto
spec:
  forwardAuth:
    address: http://mio-oauth2-oauth2-proxy.progetto.svc.cluster.local/oauth2/auth
    trustForwardHeader: true
    authResponseHeaders:
      - X-Auth-Request-User
      - X-Auth-Request-Email
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: oauth2-errors
  namespace: progetto
spec:
  errors:
    status:
      - "401"
    service:
      name: mio-oauth2-oauth2-proxy
      port: 80
    query: "/oauth2/sign_in?rd={url}"
    statusRewrites:
      "401": 302
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: oauth2-endpoints
  namespace: progetto
spec:
  entryPoints:
    - web
  routes:
    - match: "Host(`<HOST_APP>`) && PathPrefix(`/oauth2/`)"
      kind: Rule
      priority: 100
      services:
        - name: mio-oauth2-oauth2-proxy
          port: 80
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: apache-protetto
  namespace: progetto
spec:
  entryPoints:
    - web
  routes:
    - match: "Host(`<HOST_APP>`)"
      kind: Rule
      priority: 10
      middlewares:
        - name: oauth2-errors
        - name: oauth2-forwardauth
      services:
        - name: mio-apache
          port: 80
YAML



