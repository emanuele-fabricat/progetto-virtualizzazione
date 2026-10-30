#!/bin/bash
set -e
set -o pipefail

#Installazione Docker 
sudo apt update || exit 1
sudo apt install -y docker.io || exit 1
sudo systemctl enable --now docker || exit 1
sudo usermod -aG docker "$USER" || exit 1

echo -e "\033[32mINSTALLAZIONE DOCKER AVVENUTA CON SUCCESSO\033[0m"

#Installazione minikube per linux tramite binary download
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64 || exit 1
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64 || exit 1


#Avviare minikube
sudo apt-get update || exit 1
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io || exit 1
sudo systemctl enable --now docker || exit 1

# Esegui lo script come utente normale, non con "sudo ./scriptPrincipale.sh"
sudo usermod -aG docker "$USER" || exit 1

# sg avvia questi comandi con il gruppo docker attivo, senza logout/login
sg docker -c '
  set -e
  minikube config set driver docker
  minikube config set kubernetes-version v1.35.1
  minikube start
  minikube status
  minikube kubectl -- get nodes
' || exit 1

echo -e "\033[32mINSTALLAZIONE MINIKUBE AVVENUTA CON SUCCESSO\033[0m"

#Installazione helm
curl -fL --retry 3 \
  --output "$HOME/get_helm.sh" \
  'https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4' || exit 1

chmod 700 "$HOME/get_helm.sh" || exit 1
bash "$HOME/get_helm.sh" || exit 1

echo -e "\033[32mINSTALLAZIONE HELM AVVENUTA CON SUCCESSO\033[0m"

#Creazione del namespace progetto dov’è saranno messi tutti i servizi tranne linkerd
minikube kubectl -- create namespace progetto || exit 1


#Installazione bitnami
helm repo add bitnami https://charts.bitnami.com/bitnami || exit 1

echo -e "\033[32mINSTALLAZIONE REPO BITNAMI AVVENUTA CON SOCCESSO\033[0m"

#Installazione apache
helm install mio-apache oci://registry-1.docker.io/bitnamicharts/apache \
  -n progetto \
  --set service.type=ClusterIP \
  --set image.repository=bitnamilegacy/apache \
  --set image.tag=2.4.65-debian-12-r2 \
  --set image.tag=latest || exit 1

echo -e "\033[32mINSTALLAZIONE APACHE AVVENUTA CON SUCCESSO\033[0m"

#Installazione mariaDB
helm install mio-mariadb bitnami/mariadb \
  -n progetto \
  --set auth.rootPassword=Admin1234! \
  --set image.repository=bitnamilegacy/mariadb \
  --set global.security.allowInsecureImages=true \
  --set auth.database=miodb \
  --set auth.username=admin \
  --set auth.password=Admin1234! || exit 1

echo -e "\033[32mINSTALLAZIONE MARIADB AVVENUTA CON SUCCESSO\033[0m"

#Installazione keycloak con postgress
helm install mio-keycloak bitnami/keycloak \
  -n progetto \
  --set image.repository=bitnamilegacy/keycloak \
  --set image.tag=26.3.3-debian-12-r0 \
  --set service.type=NodePort \
  --set service.nodePorts.http=32622 \
  --set postgresql.image.repository=bitnamilegacy/postgresql \
  --set postgresql.image.tag=17.6.0-debian-12-r0 \
  --set global.security.allowInsecureImages=true \
  --set auth.adminUser=admin \
  --set auth.adminPassword=Admin1234! \
  --set postgresql.auth.postgresPassword=Admin1234! \
  --set postgresql.auth.username=admin \
  --set postgresql.auth.password=Admin1234! \
  --set postgresql.auth.database=keycloak_db || exit 1

echo -e "\033[32mINSTALLAZIONE KEYCLOAK AVVENUTA CON SUCCESSO\033[0m"

#Installazione traefik
helm repo add traefik https://traefik.github.io/charts || exit 1
helm repo update || exit 1
helm upgrade --install traefik traefik/traefik \
  -n progetto || exit 1

echo -e "\033[32mINSTALLAZIONE TRAEFIK AVVENUTA CON SUCCESSO\033[0m"

bash "$HOME/progetto-virtualizzazione/modificaYamlTraefik.sh" || exit 1

echo -e "\033[32m MODIFICA DELLO YAML DI TRAEFIK AVVENUTE CON SUCCESSO\033[0m"

minikube start || exit 1

echo -e "\033[32mQUANDO TUTTI I POD RISULTANO IN STATO RUNNING e NELLA COLONNA READY 1/1 APRIRE IL FILE settingKeycloak.txt ED ESEGUIRE PASSO PASSO I COMANDI ALL'INTENRO\033[0m"
echo -e "\033[93mNOTA BENE: il fatto che alcuni pod risultino in READY = 0/1 dopo diversi restarts non è un prblema, basta attendere qualche tentativo in fine quando tutto risulta in stato 1/1 premere ctrl+C\033[0m"
 
minikube kubectl -- get pods -n progetto -w || exit 1
