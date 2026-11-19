#!/bin/bash
set -euo pipefail

# Senza argomenti: seconda fase completa del progetto.
# --solo-keycloak: ripara una installazione esistente, senza Helm né secret OAuth.
# --solo-policy-web: applica soltanto le due NetworkPolicy di ingresso per Traefik
# su Keycloak e Apache; nessuna reiniezione, reinstallazione o rotazione dei secret.
# --diagnosi: sola lettura, utile anche se il rollout è fallito.
NS=progetto
KC=mio-keycloak
PG=mio-keycloak-postgresql
PROFILE=${MINIKUBE_PROFILE:-minikube}
export PATH="$HOME/.linkerd2/bin:$PATH"
mk() { minikube -p "$PROFILE" "$@"; }
k()  { mk kubectl -- -n "$NS" "$@"; }
ld() { linkerd --context "$PROFILE" "$@"; }

nomi_container() {
  k get "pod/$1" --ignore-not-found -o go-template='{{range .spec.containers}}{{.name}} {{end}}{{range .spec.initContainers}}{{.name}} {{end}}'
}

# Modifica il template, non esportare/riapplicare l'intero oggetto gestito da Helm.
# Con la strategia RollingUpdate del progetto basta questa modifica a ricreare i Pod.
mesh_rollout() {
  local risorsa=$1 annotazioni=$2 pod_verifica=${3:-} prima dopo nomi
  echo "Mesh: $risorsa"
  prima=$(k get "$risorsa" -o jsonpath='{.metadata.generation}')
  dopo=$(k patch "$risorsa" --type=merge \
    -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":$annotazioni}}}}" \
    -o jsonpath='{.metadata.generation}')
  # Caso di recupero: il template era GIA' corretto, ma il Pod precede il webhook.
  if [[ -n $pod_verifica && $prima == "$dopo" ]]; then
    nomi=$(nomi_container "$pod_verifica")
    if [[ -n $nomi && " $nomi " != *' linkerd-proxy '* ]]; then
      k rollout restart "$risorsa"
    fi
  fi
  k rollout status "$risorsa" --timeout="${ROLLOUT_TIMEOUT:-10m}"
  if [[ -n $pod_verifica ]]; then
    nomi=$(nomi_container "$pod_verifica")
    if [[ " $nomi " != *' linkerd-proxy '* ]]; then
      echo "Il Pod $pod_verifica non contiene linkerd-proxy. Controlla il webhook con --diagnosi." >&2
      return 1
    fi
  fi
}

# Le policy Bitnami possono consentire la porta dell'app ma NON la porta inbound
# del proxy. Aggiungi un permesso mirato solo se una policy del chart isola già
# in ingresso i Pod; non creare il primo isolamento di un Pod altrimenti aperto.
consenti_proxy() {
  local policy=$1 sorgente=$2 tipi dst src
  tipi=$(k get "networkpolicy/$policy" --ignore-not-found -o jsonpath='{.spec.policyTypes[*]}')
  [[ " $tipi " == *' Ingress '* ]] || return 0
  dst=$(k get "networkpolicy/$policy" -o jsonpath='{.spec.podSelector}')
  src=$(k get "$sorgente" -o jsonpath='{.spec.selector}')
  if [[ -z $dst || $dst == '{}' || -z $src || $src == '{}' ]]; then
    echo "Selettore mancante per $policy o $sorgente: non apro la porta 4143." >&2
    return 1
  fi
  k apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${policy}-ingresso-linkerd
  namespace: ${NS}
spec:
  podSelector: ${dst}
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector: ${src}
      ports:
        - {protocol: TCP, port: 4143}
YAML
}

mesh_keycloak() {
  local hl
  # La porta è opaca sulla destinazione PostgreSQL, NON sull'HTTP di Keycloak.
  hl=$(k get "statefulset/$PG" -o jsonpath='{.spec.serviceName}')
  k annotate "service/$PG" config.linkerd.io/opaque-ports=5432 --overwrite
  if [[ -n $hl && $hl != "$PG" ]]; then
    k annotate "service/$hl" config.linkerd.io/opaque-ports=5432 --overwrite
  fi
  consenti_proxy "$PG" "statefulset/$KC"        # Keycloak -> PostgreSQL
  consenti_proxy "$KC" deployment/traefik       # Traefik -> Keycloak (issuer OIDC)

  mesh_rollout "statefulset/$PG" \
    '{"linkerd.io/inject":"enabled","config.linkerd.io/opaque-ports":"5432"}' "${PG}-0"
  # pg_isready verifica l'ascolto del server, NON le credenziali JDBC di Keycloak.
  k exec "${PG}-0" -c postgresql -- pg_isready -h 127.0.0.1 -p 5432 -U admin -d keycloak_db
  mesh_rollout "statefulset/$KC" \
    '{"linkerd.io/inject":"enabled","config.linkerd.io/proxy-await":"enabled"}' "${KC}-0"
  k get pod "${PG}-0" "${KC}-0"
}

diagnosi() {
  mk kubectl -- -n linkerd get deployment/linkerd-proxy-injector --ignore-not-found -o wide
  k get statefulset "$PG" "$KC" --ignore-not-found -o wide
  k get pod "${PG}-0" "${KC}-0" --ignore-not-found \
    -o 'custom-columns=POD:.metadata.name,FASE:.status.phase,APP:.spec.containers[*].name,INIT:.spec.initContainers[*].name,READY:.status.containerStatuses[*].ready,RESTART:.status.containerStatuses[*].restartCount,ULTIMO_STOP:.status.containerStatuses[*].lastState.terminated.reason,INIT_ULTIMO_STOP:.status.initContainerStatuses[*].lastState.terminated.reason'
  k get endpointslice -l "kubernetes.io/service-name=$PG" \
    -o 'custom-columns=SLICE:.metadata.name,INDIRIZZI:.endpoints[*].addresses[*],READY:.endpoints[*].conditions.ready,PORTA:.ports[*].port'
  k get networkpolicy
  local voce
  for voce in "${KC}-0:keycloak" "${KC}-0:linkerd-proxy" "${PG}-0:postgresql" "${PG}-0:linkerd-proxy"; do
    echo "--- ${voce%:*} / ${voce#*:} ---"
    k logs "${voce%:*}" -c "${voce#*:}" --tail=50 || true
  done
  echo '--- Keycloak: ultimo avvio precedente (se presente) ---'
  k logs "${KC}-0" -c keycloak --previous --tail=50 2>/dev/null || true
  echo '--- Eventi Warning del namespace ---'
  k get events --field-selector type=Warning --sort-by=.metadata.creationTimestamp | tail -n 25
}

if (( $# > 1 )); then echo "Uso: bash $0 [--solo-keycloak|--solo-policy-web|--diagnosi]" >&2; exit 2; fi
case "${1:-}" in
  --diagnosi) diagnosi; exit 0 ;;
  --solo-policy-web)
    consenti_proxy "$KC" deployment/traefik
    consenti_proxy mio-apache deployment/traefik
    # Mostra i due nomi prima dell'eventuale rimozione delle policy di prova.
    k get networkpolicy "${KC}-ingresso-linkerd" mio-apache-ingresso-linkerd -o name
    exit 0 ;;
  --solo-keycloak)
    ld check --wait 5m
    mesh_keycloak
    exit 0 ;;
  '') ;;
  *) echo "Uso: bash $0 [--solo-keycloak|--solo-policy-web|--diagnosi]" >&2; exit 2 ;;
esac

echo "Nel prossimo comando sarà richiesta il client secret, immettere quello salvato nel passo precedente"

#Creazione secret kubernetes
read -r -s -p 'Client secret Keycloak: ' KC_CLIENT_SECRET
printf '\n'
COOKIE_SECRET="$(openssl rand -hex 16)"
COOKIE_SECRET_B64="$(printf '%s' "$COOKIE_SECRET" | base64 -w0)"
MINIKUBE_IP="$(mk ip)" || exit 1
TRAEFIK_NODE_PORT="$(mk kubectl -- get service traefik -n progetto \
  -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')" || exit 1
if [[ -z "$TRAEFIK_NODE_PORT" ]]; then
  echo "Impossibile determinare la porta NodePort HTTP assegnata a Traefik" >&2
  exit 1
fi
KEYCLOAK_ISSUER_URL="http://${MINIKUBE_IP}:${TRAEFIK_NODE_PORT}/realms/progetto"

mk kubectl -- apply -f - <<YAML || exit 1
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: keycloak-minikube-ip
  namespace: progetto
spec:
  entryPoints:
    - web
  routes:
    - match: Host(\`${MINIKUBE_IP}\`)
      kind: Rule
      services:
        - name: mio-keycloak
          port: 80
          nativeLB: true
YAML

mk kubectl -- create secret generic mio-oauth2-keycloak \
  -n progetto \
  --from-literal=client-id='oauth2-proxy' \
  --from-literal=client-secret="$KC_CLIENT_SECRET" \
  --from-literal=cookie-secret="$COOKIE_SECRET_B64" \
  --dry-run=client -o yaml | mk kubectl -- apply -f - || exit 1

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
EOF

echo -e "\033[32mMIDIFICA YAML DEL SECRET AVVENUTA CON SUCCESSO\033[0m"

#Installazione Oauth2-proxy
helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests || exit 1
helm repo update || exit 1
helm upgrade --install mio-oauth2 oauth2-proxy/oauth2-proxy \
  -n progetto \
  --kube-context "$PROFILE" -f oauth2-keycloak-values.yaml || exit 1

echo -e "\033[32mINSTALLAZIONE OAUTH2-PROXY AVVENUTA CON SUCCESSO\033[0m"


# Installa la CLI prevista dal progetto e rendila disponibile anche alle shell future.
export LINKERD2_VERSION=edge-26.10.1
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
touch "$HOME/.bashrc"
if ! grep -Fqx 'export PATH="$HOME/.linkerd2/bin:$PATH"' "$HOME/.bashrc"; then
  printf '\n%s\n' 'export PATH="$HOME/.linkerd2/bin:$PATH"' >> "$HOME/.bashrc"
fi

# Non rigenerare identità/certificati di un control plane esistente.
injector=$(mk kubectl -- -n linkerd get deployment/linkerd-proxy-injector --ignore-not-found -o name)
if [[ -z $injector ]]; then
  mk kubectl -- apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
  ld check --pre
  ld install --crds | mk kubectl -- apply -f -
  ld install | mk kubectl -- apply -f -
fi
ld check --wait 5m
viz=$(mk kubectl -- -n linkerd-viz get deployment/metrics-api --ignore-not-found -o name)
if [[ -z $viz ]]; then
  ld viz install | mk kubectl -- apply -f -
fi

# Prima la dipendenza (PostgreSQL), poi Keycloak, infine i client HTTP.
mesh_keycloak
# La 8080 applicativa di Apache non basta al trasporto tra i due proxy.
consenti_proxy mio-apache deployment/traefik
for risorsa in deployment/traefik deployment/mio-oauth2-oauth2-proxy deployment/mio-apache statefulset/mio-mariadb; do
  mesh_rollout "$risorsa" '{"linkerd.io/inject":"enabled"}'
done
ld check --proxy --namespace "$NS" --wait 5m
