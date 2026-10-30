#!/bin/bash
set -e
set -o pipefail

echo "Nel prossimo comando sarà richiesta il client secret, immettere quello salvato nel passo precedente"

#Creazione secret kubernetes
read -r -s -p 'Client secret Keycloak: ' KC_CLIENT_SECRET
printf '\n'
COOKIE_SECRET="$(openssl rand -hex 16)"
COOKIE_SECRET_B64="$(printf '%s' "$COOKIE_SECRET" | base64 -w0)"
MINIKUBE_IP="$(minikube ip)" || exit 1
KEYCLOAK_ISSUER_URL="http://${MINIKUBE_IP}:32622/realms/progetto"

minikube kubectl -- create secret generic mio-oauth2-keycloak \
  -n progetto \
  --from-literal=client-id='oauth2-proxy' \
  --from-literal=client-secret="$KC_CLIENT_SECRET" \
  --from-literal=cookie-secret="$COOKIE_SECRET_B64" \
  --dry-run=client -o yaml | minikube kubectl -- apply -f - || exit 1

unset KC_CLIENT_SECRET COOKIE_SECRET COOKIE_SECRET_B64

echo -e "\033[32mCREAZIONE SECRET AVVENUTA CON SUCCESSO\033[0m"

#Preparazione valori Helm
cat > oauth2-keycloak-values.yaml <<EOF
config:
  existingSecret: mio-oauth2-keycloak

extraArgs:
  provider: "keycloak-oidc"
  oidc-issuer-url: "${KEYCLOAK_ISSUER_URL}"
  redirect-url: "http://localhost:8081/oauth2/callback"
  skip-provider-button: "true"
  reverse-proxy: "true"
  cookie-secure: "false"
  whitelist-domain: "localhost:8081"
  set-xauthrequest: "true"
podAnnotations:
  linkerd.io/inject: "enabled"
EOF

echo -e "\033[32mMIDIFICA YAML DEL SECRET AVVENUTA CON SUCCESSO\033[0m"

#Installazione Oauth2-proxy
helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests || exit 1
helm repo update || exit 1
helm upgrade --install mio-oauth2 oauth2-proxy/oauth2-proxy \
  -n progetto \
  -f oauth2-keycloak-values.yaml || exit 1

echo -e "\033[32mINSTALLAZIONE OAUTH2-PROXY AVVENUTA CON SUCCESSO\033[0m"

#Installazione linkerd tramite guida ufficiale https://linkerd.io/docs/getting-started/
# Setting LINKERD2_VERSION sets the version to install.
# If unset, you'll get the latest available edge version.
export LINKERD2_VERSION=edge-26.10.1
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh || exit 1
LINKERD_BIN="$HOME/.linkerd2/bin"
export PATH="$LINKERD_BIN:$PATH"
touch "$HOME/.bashrc"
if ! grep -Fqx 'export PATH="$HOME/.linkerd2/bin:$PATH"' "$HOME/.bashrc"; then
  printf '\n%s\n' 'export PATH="$HOME/.linkerd2/bin:$PATH"' >> "$HOME/.bashrc"
fi
#Isntallazione Gatewai API GRD

minikube kubectl -- apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml || exit 1

#Controllo installazione linkerd version
#controllo che il sistema possa installare linkerd: 
linkerd check --pre || exit 1
linkerd install --crds | minikube kubectl -- apply -f - || exit 1
linkerd install | minikube kubectl -- apply -f - || exit 1
linkerd viz install | minikube kubectl -- apply -f - || exit 1

#Controllo linkerd funzioni: 
linkerd check || exit 1

echo -e "\033[32mINSTALLAZIONE LINKERD AVVENUTA CON SUCCESSO\033[0m"

#Mashing di apache
minikube kubectl -- get deploy mio-apache -n progetto -o yaml \
  | linkerd --linkerd-namespace linkerd inject - \
  | minikube kubectl -- apply -f - || exit 1

minikube kubectl -- rollout status deployment/mio-apache -n progetto || exit 1
#Per prova minikube kubectl -- -n progetto port-forward svc/mio-apache 8080:80

echo -e "\033[32mINIEZIONE DI APACHE IN LINKERD AVVENUTA CON SUCCESSO\033[0m"

#Mashing Oauth2-Proxy
minikube kubectl -- get deployment mio-oauth2-oauth2-proxy -n progetto -o yaml \
  | linkerd --linkerd-namespace linkerd inject - \
  | minikube kubectl -- apply -f - || exit 1

minikube kubectl -- rollout status deployment/mio-oauth2-oauth2-proxy -n progetto --timeout=180s || exit 1

echo -e "\033[32mINIEZIONE DI OAUTH2-PROXY IN LINKERD AVVENUTA CON SUCCESSO\033[0m"

#Mashing Keycloak
minikube kubectl -- get statefulset mio-keycloak -n progetto -o yaml \
  | linkerd --linkerd-namespace linkerd inject - \
  | minikube kubectl -- apply -f - || exit 1

minikube kubectl -- rollout status statefulset/mio-keycloak -n progetto --timeout=300s || exit 1

echo -e "\033[32mINIEZIONE DI KEYCLOACK IN LINKERD AVVENUTA CON SUCCESSO\033[0m"

#Mashing treafik
minikube kubectl -- get deployment traefik -n progetto -o yaml \
  | linkerd --linkerd-namespace linkerd inject - \
  | minikube kubectl -- apply -f - || exit 1

minikube kubectl -- rollout status deployment/traefik -n progetto --timeout=180s || exit 1

echo -e "\033[32mINIEZIONE DI TRAEFIK IN LINKERD AVVENUTA CON SUCCESSO\033[0m"

#Mashing maria-db
minikube kubectl -- get statefulset mio-mariadb -n progetto -o yaml \
  | linkerd --linkerd-namespace linkerd inject - \
  | minikube kubectl -- apply -f - || exit 1

minikube kubectl -- rollout status statefulset/mio-mariadb -n progetto --timeout=300s || exit 1

echo -e "\033[32mINIEZIONE DI MARIA-DB IN LINKERD AVVENUTA CON SUCCESSO\033[0m"

#Mashing postgress
minikube kubectl -- get statefulset mio-keycloak-postgresql -n progetto -o yaml \
  | linkerd --linkerd-namespace linkerd inject - \
  | minikube kubectl -- apply -f - || exit 1

minikube kubectl -- rollout status statefulset/mio-keycloak-postgresql -n progetto --timeout=300s || exit 1

echo -e "\033[32mINIEZIONE DI POSTGRESS IN LINKERD AVVENUTA CON SUCCESSO\033[0m"

