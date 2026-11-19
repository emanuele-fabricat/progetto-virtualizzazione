#!/bin/bash
set -euo pipefail

NS=progetto
KC=mio-keycloak
PG=mio-keycloak-postgresql
PROFILE=${MINIKUBE_PROFILE:-minikube}
export PATH="$HOME/.linkerd2/bin:$PATH"

mk() { minikube -p "$PROFILE" "$@"; }
k()  { mk kubectl -- -n "$NS" "$@"; }
ld() { linkerd --context "$PROFILE" "$@"; }

echo "Client secret Keycloak:"
read -r -s KC_CLIENT_SECRET
printf '\n'

COOKIE_SECRET="$(openssl rand -hex 16)"
COOKIE_SECRET_B64="$(printf '%s' "$COOKIE_SECRET" | base64 -w0)"
MINIKUBE_IP="$(mk ip)"
TRAEFIK_NODE_PORT="$(mk kubectl -- get service traefik -n "$NS" \
  -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')"

test -n "$TRAEFIK_NODE_PORT" || {
  echo "Impossibile determinare la NodePort HTTP di Traefik" >&2
  exit 1
}

KEYCLOAK_ISSUER_URL="http://${MINIKUBE_IP}:${TRAEFIK_NODE_PORT}/realms/progetto"

mk kubectl -- apply -f - <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: keycloak-minikube-ip
  namespace: $NS
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`$MINIKUBE_IP`)
      kind: Rule
      services:
        - name: $KC
          port: 80
          nativeLB: true
YAML

mk kubectl -- create secret generic mio-oauth2-keycloak \
  -n "$NS" \
  --from-literal=client-id='oauth2-proxy' \
  --from-literal=client-secret="$KC_CLIENT_SECRET" \
  --from-literal=cookie-secret="$COOKIE_SECRET_B64" \
  --dry-run=client -o yaml |
  mk kubectl -- apply -f -

unset KC_CLIENT_SECRET COOKIE_SECRET COOKIE_SECRET_B64

cat > oauth2-keycloak-values.yaml <<EOF
config:
  existingSecret: mio-oauth2-keycloak

extraArgs:
  provider: "keycloak-oidc"
  oidc-issuer-url: "$KEYCLOAK_ISSUER_URL"
  redirect-url: "http://localhost:8081/oauth2/callback"
  skip-provider-button: "true"
  reverse-proxy: "true"
  cookie-secure: "false"
  whitelist-domain: "localhost:8081"
  set-xauthrequest: "true"
EOF

helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
helm repo update
helm upgrade --install mio-oauth2 oauth2-proxy/oauth2-proxy \
  -n "$NS" \
  --kube-context "$PROFILE" \
  -f oauth2-keycloak-values.yaml

export LINKERD2_VERSION=edge-26.10.1
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
touch "$HOME/.bashrc"
grep -Fqx 'export PATH="$HOME/.linkerd2/bin:$PATH"' "$HOME/.bashrc" ||
  printf '\n%s\n' 'export PATH="$HOME/.linkerd2/bin:$PATH"' >> "$HOME/.bashrc"

INJECTOR="$(mk kubectl -- -n linkerd get deployment/linkerd-proxy-injector \
  --ignore-not-found -o name)"
if [[ -z "$INJECTOR" ]]; then
  mk kubectl -- apply --server-side -f \
    https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
  ld check --pre
  ld install --crds | mk kubectl -- apply -f -
  ld install | mk kubectl -- apply -f -
fi

ld check --wait 5m

VIZ="$(mk kubectl -- -n linkerd-viz get deployment/metrics-api \
  --ignore-not-found -o name)"
if [[ -z "$VIZ" ]]; then
  ld viz install | mk kubectl -- apply -f -
fi

# PostgreSQL usa il protocollo opaco 5432.
HEADLESS_SERVICE="$(k get "statefulset/$PG" -o jsonpath='{.spec.serviceName}')"
k annotate "service/$PG" config.linkerd.io/opaque-ports=5432 --overwrite
if [[ -n "$HEADLESS_SERVICE" && "$HEADLESS_SERVICE" != "$PG" ]]; then
  k annotate "service/$HEADLESS_SERVICE" config.linkerd.io/opaque-ports=5432 --overwrite
fi

consenti_proxy() {
  local policy=$1 sorgente=$2 dst src tipi
  tipi=$(k get "networkpolicy/$policy" --ignore-not-found -o jsonpath='{.spec.policyTypes[*]}')
  [[ " $tipi " == *' Ingress '* ]] || return 0

  dst=$(k get "networkpolicy/$policy" -o jsonpath='{.spec.podSelector}')
  src=$(k get "$sorgente" -o jsonpath='{.spec.selector}')
  k apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${policy}-ingresso-linkerd
  namespace: $NS
spec:
  podSelector: $dst
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector: $src
      ports:
        - {protocol: TCP, port: 4143}
YAML
}

consenti_proxy "$PG" "statefulset/$KC"
consenti_proxy "$KC" deployment/traefik
consenti_proxy mio-apache deployment/traefik

mesh_rollout() {
  local risorsa=$1 annotazioni=$2 pod_verifica=${3:-}
  local nomi

  k patch "$risorsa" --type=merge \
    -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":$annotazioni}}}}"
  k rollout status "$risorsa" --timeout="${ROLLOUT_TIMEOUT:-10m}"

  if [[ -n "$pod_verifica" ]]; then
    nomi=$(k get "pod/$pod_verifica" --ignore-not-found \
      -o go-template='{{range .spec.containers}}{{.name}} {{end}}{{range .spec.initContainers}}{{.name}} {{end}}')
    [[ " $nomi " == *' linkerd-proxy '* ]] || {
      echo "Il Pod $pod_verifica non contiene linkerd-proxy" >&2
      exit 1
    }
  fi
}

mesh_rollout "statefulset/$PG" \
  '{"linkerd.io/inject":"enabled","config.linkerd.io/opaque-ports":"5432"}' "${PG}-0"
k exec "${PG}-0" -c postgresql -- pg_isready -h 127.0.0.1 -p 5432 -U admin -d keycloak_db

mesh_rollout "statefulset/$KC" \
  '{"linkerd.io/inject":"enabled","config.linkerd.io/proxy-await":"enabled"}' "${KC}-0"

for risorsa in \
  deployment/traefik \
  deployment/mio-oauth2-oauth2-proxy \
  deployment/mio-apache \
  statefulset/mio-mariadb
do
  mesh_rollout "$risorsa" '{"linkerd.io/inject":"enabled"}'
done

k get pod "${PG}-0" "${KC}-0"
ld check --proxy --namespace "$NS" --wait 5m
