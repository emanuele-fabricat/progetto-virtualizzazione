#!/bin/bash
# La modalità Bash è necessaria per le espansioni e le strutture di controllo usate sotto.
# Interrompe al primo errore, su variabili non definite e sugli errori nelle pipeline.
set -euo pipefail

# Namespace Kubernetes dell'applicazione.
NS=progetto
# Nome del StatefulSet di Keycloak.
KC=mio-keycloak
# Nome del StatefulSet PostgreSQL usato da Keycloak.
PG=mio-keycloak-postgresql
# Usa il profilo Minikube indicato nell'ambiente o quello predefinito.
PROFILE=${MINIKUBE_PROFILE:-minikube}
# Salva l'eventuale opzione passata allo script.
MODE=${1:-}
# Aggiunge la CLI Linkerd installata nella directory utente al PATH corrente.
export PATH="$HOME/.linkerd2/bin:$PATH"

# Accetta al massimo un'opzione e rifiuta quelle non previste.
if (( $# > 1 )) || [[ -n $MODE && $MODE != --solo-keycloak && $MODE != --solo-policy-web && $MODE != --diagnosi ]]; then
  # Mostra l'uso sullo standard error.
  echo "Uso: bash $0 [--solo-keycloak|--solo-policy-web|--diagnosi]" >&2
  # Segnala un errore nella riga di comando.
  exit 2
fi

# Avvia la modalità di sola diagnosi senza eseguire modifiche al cluster.
if [[ $MODE == --diagnosi ]]; then
  # Mostra lo stato del controller Linkerd che inietta i proxy.
  minikube -p "$PROFILE" kubectl -- -n linkerd get deployment/linkerd-proxy-injector --ignore-not-found -o wide
  # Mostra lo stato dei StatefulSet PostgreSQL e Keycloak.
  minikube -p "$PROFILE" kubectl -- -n "$NS" get statefulset "$PG" "$KC" --ignore-not-found -o wide
  # Riepiloga stato, container, readiness e riavvii dei pod principali.
  minikube -p "$PROFILE" kubectl -- -n "$NS" get pod "${PG}-0" "${KC}-0" --ignore-not-found \
    -o 'custom-columns=POD:.metadata.name,FASE:.status.phase,APP:.spec.containers[*].name,INIT:.spec.initContainers[*].name,READY:.status.containerStatuses[*].ready,RESTART:.status.containerStatuses[*].restartCount,ULTIMO_STOP:.status.containerStatuses[*].lastState.terminated.reason,INIT_ULTIMO_STOP:.status.initContainerStatuses[*].lastState.terminated.reason'
  # Mostra gli EndpointSlice associati al Service PostgreSQL e il loro stato.
  minikube -p "$PROFILE" kubectl -- -n "$NS" get endpointslice -l "kubernetes.io/service-name=$PG" \
    -o 'custom-columns=SLICE:.metadata.name,INDIRIZZI:.endpoints[*].addresses[*],READY:.endpoints[*].conditions.ready,PORTA:.ports[*].port'
  # Elenca le NetworkPolicy del namespace per diagnosticare eventuali blocchi di rete.
  minikube -p "$PROFILE" kubectl -- -n "$NS" get networkpolicy

  # Legge i log dei container applicativi e dei proxy Linkerd dei due StatefulSet.
  for voce in "${KC}-0:keycloak" "${KC}-0:linkerd-proxy" "${PG}-0:postgresql" "${PG}-0:linkerd-proxy"; do
    # Estrae il nome del pod dalla parte prima dei due punti.
    pod=${voce%:*}
    # Estrae il nome del container dalla parte dopo i due punti.
    container=${voce#*:}
    # Stampa un'intestazione per distinguere i log nel terminale.
    echo "--- $pod / $container ---"
    # Legge le ultime 50 righe; continua se il pod o il container non è disponibile.
    minikube -p "$PROFILE" kubectl -- -n "$NS" logs "$pod" -c "$container" --tail=50 || true
  done
  # Indica la sezione dei log dell'avvio precedente di Keycloak.
  echo '--- Keycloak: ultimo avvio precedente (se presente) ---'
  # Mostra i log precedenti, ignorando l'errore se non esistono.
  minikube -p "$PROFILE" kubectl -- -n "$NS" logs "${KC}-0" -c keycloak --previous --tail=50 2>/dev/null || true
  # Indica la sezione degli eventi Kubernetes di tipo Warning.
  echo '--- Eventi Warning del namespace ---'
  # Ordina gli eventi per data e limita la stampa ai 25 più recenti.
  minikube -p "$PROFILE" kubectl -- -n "$NS" get events --field-selector type=Warning --sort-by=.metadata.creationTimestamp | tail -n 25
  # Termina qui: la diagnostica non deve procedere con l'installazione.
  exit 0
fi

# Questa opzione applica soltanto le policy di ingresso per Keycloak e Apache.
if [[ $MODE == --solo-policy-web ]]; then
  # Esamina le policy di entrambi i servizi che ricevono richieste da Traefik.
  for voce in "$KC deployment/traefik" "mio-apache deployment/traefik"; do
    # Divide il nome della policy dal workload sorgente.
    read -r policy sorgente <<< "$voce"
    # Recupera i tipi di traffico gestiti dalla policy; se assente, ottiene una stringa vuota.
    tipi=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "networkpolicy/$policy" --ignore-not-found -o jsonpath='{.spec.policyTypes[*]}')
    # Aggiunge una regola solo quando la policy esistente isola l'ingresso.
    if [[ " $tipi " == *' Ingress '* ]]; then
      # Legge il selettore dei pod a cui si applica la policy.
      dst=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "networkpolicy/$policy" -o jsonpath='{.spec.podSelector}')
      # Legge il selettore dei pod Traefik che devono poter raggiungere il proxy.
      src=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "$sorgente" -o jsonpath='{.spec.selector}')
      # Blocca la modifica se uno dei selettori è mancante o vuoto.
      if [[ -z $dst || $dst == '{}' || -z $src || $src == '{}' ]]; then
        # Spiega perché non è sicuro creare la regola di rete.
        echo "Selettore mancante per $policy o $sorgente: non apro la porta 4143." >&2
        # Interrompe l'esecuzione per non proseguire con una policy incompleta.
        exit 1
      fi
      # Applica una NetworkPolicy limitata alla porta inbound del proxy Linkerd.
      minikube -p "$PROFILE" kubectl -- -n "$NS" apply -f - <<YAML
# Versione API Kubernetes delle NetworkPolicy.
apiVersion: networking.k8s.io/v1
# Tipo di oggetto da applicare.
kind: NetworkPolicy
# Nome della nuova regola e namespace di destinazione.
metadata:
  name: ${policy}-ingresso-linkerd
  namespace: ${NS}
# Definisce i pod coinvolti e il traffico autorizzato.
spec:
  # Riutilizza il selettore di destinazione della policy originale.
  podSelector: ${dst}
  # Dichiara che la regola governa il traffico in ingresso.
  policyTypes: [Ingress]
  # Elenco delle regole di ingresso consentite.
  ingress:
    # Limita il traffico ammesso alla sorgente selezionata sotto.
    - from:
        # Selettore dei pod Traefik autorizzati.
        - podSelector: ${src}
      # Limita la connessione autorizzata alla porta del proxy.
      ports:
        # Consente esclusivamente TCP sulla porta inbound 4143 di Linkerd.
        - {protocol: TCP, port: 4143}
YAML
    fi
  done
  # Mostra i nomi delle policy aggiuntive; kubectl segnala se una non esiste.
  minikube -p "$PROFILE" kubectl -- -n "$NS" get networkpolicy "${KC}-ingresso-linkerd" mio-apache-ingresso-linkerd -o name
  # Evita di proseguire con secret, Helm e installazione Linkerd.
  exit 0
fi

if [[ $MODE != --solo-keycloak ]]; then
  # Avvisa l'utente che verrà richiesto il client secret di Keycloak.
  echo "Nel prossimo comando sarà richiesta il client secret, immettere quello salvato nel passo precedente"
  # Legge il secret senza mostrarlo sul terminale.
  read -r -s -p 'Client secret Keycloak: ' KC_CLIENT_SECRET
  # Va a capo dopo l'input nascosto.
  printf '\n'

  # Genera un segreto casuale per la firma dei cookie OAuth2 Proxy.
  COOKIE_SECRET="$(openssl rand -hex 16)"
  # Codifica il valore generato nel formato Base64 richiesto.
  COOKIE_SECRET_B64="$(printf '%s' "$COOKIE_SECRET" | base64 -w0)"
  # Recupera l'indirizzo IP assegnato al nodo Minikube.
  MINIKUBE_IP="$(minikube -p "$PROFILE" ip)"
  # Legge la NodePort HTTP assegnata al Service Traefik.
  TRAEFIK_NODE_PORT="$(minikube -p "$PROFILE" kubectl -- get service traefik -n "$NS" \
    -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')"
  # Interrompe se Traefik non espone una porta HTTP raggiungibile.
  if [[ -z $TRAEFIK_NODE_PORT ]]; then
    # Comunica l'errore sullo standard error.
    echo "Impossibile determinare la porta NodePort HTTP assegnata a Traefik" >&2
    # Evita di procedere con un URL issuer incompleto.
    exit 1
  fi
  # Compone l'issuer OIDC raggiungibile da OAuth2 Proxy.
  KEYCLOAK_ISSUER_URL="http://${MINIKUBE_IP}:${TRAEFIK_NODE_PORT}/realms/progetto"

  # Crea la route Traefik che inoltra le richieste dirette all'IP Minikube a Keycloak.
  minikube -p "$PROFILE" kubectl -- apply -f - <<YAML
# Versione API Traefik della risorsa IngressRoute.
apiVersion: traefik.io/v1alpha1
# Tipo di oggetto Kubernetes da applicare.
kind: IngressRoute
# Nome e namespace della route.
metadata:
  name: keycloak-minikube-ip
  namespace: ${NS}
# Parametri del listener HTTP e della destinazione.
spec:
  # Usa il punto d'ingresso HTTP di Traefik.
  entryPoints:
    - web
  # Definisce le regole della route.
  routes:
    # Corrisponde alle richieste che hanno l'IP Minikube come Host.
    - match: Host(\`${MINIKUBE_IP}\`)
      # Specifica la sintassi standard delle regole Traefik.
      kind: Rule
      # Inoltra al servizio Kubernetes di Keycloak.
      services:
        - name: ${KC}
          # Porta HTTP del servizio Keycloak.
          port: 80
          # Bilancia le richieste direttamente sugli endpoint del servizio.
          nativeLB: true
YAML

  # Genera il manifest del Secret e lo applica nel namespace dell'applicazione.
  minikube -p "$PROFILE" kubectl -- create secret generic mio-oauth2-keycloak \
    -n "$NS" \
    --from-literal=client-id='oauth2-proxy' \
    --from-literal=client-secret="$KC_CLIENT_SECRET" \
    --from-literal=cookie-secret="$COOKIE_SECRET_B64" \
    --dry-run=client -o yaml | minikube -p "$PROFILE" kubectl -- apply -f -
  # Rimuove i valori sensibili dalla memoria della shell dopo l'applicazione.
  unset KC_CLIENT_SECRET COOKIE_SECRET COOKIE_SECRET_B64

  # Conferma che il Secret sia stato creato o aggiornato.
  echo -e "\033[32mCREAZIONE SECRET AVVENUTA CON SUCCESSO\033[0m"

  # Crea il file dei valori Helm per configurare OAuth2 Proxy.
  cat > oauth2-keycloak-values.yaml <<EOF
# Indica al chart di riutilizzare il Secret Kubernetes esistente.
config:
  existingSecret: mio-oauth2-keycloak

# Argomenti passati al processo OAuth2 Proxy.
extraArgs:
  # Seleziona Keycloak come provider OIDC.
  provider: "keycloak-oidc"
  # Imposta l'issuer costruito con IP e NodePort di Minikube.
  oidc-issuer-url: "${KEYCLOAK_ISSUER_URL}"
  # URL callback configurato nel client OAuth.
  redirect-url: "http://localhost:8081/oauth2/callback"
  # Evita la pagina di selezione del provider.
  skip-provider-button: "true"
  # Segnala che OAuth2 Proxy opera dietro un reverse proxy.
  reverse-proxy: "true"
  # Consente cookie non Secure nell'ambiente locale HTTP.
  cookie-secure: "false"
  # Limita il dominio autorizzato al servizio locale.
  whitelist-domain: "localhost:8081"
  # Abilita gli header di autenticazione attesi dai servizi downstream.
  set-xauthrequest: "true"
EOF

  # Conferma la generazione del file di configurazione Helm.
  echo -e "\033[32mMIDIFICA YAML DEL SECRET AVVENUTA CON SUCCESSO\033[0m"

  # Registra il repository ufficiale dei chart OAuth2 Proxy.
  helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
  # Aggiorna l'indice locale dei chart disponibili.
  helm repo update
  # Installa o aggiorna OAuth2 Proxy nel namespace e nel contesto selezionati.
  helm upgrade --install mio-oauth2 oauth2-proxy/oauth2-proxy \
    -n "$NS" --kube-context "$PROFILE" -f oauth2-keycloak-values.yaml

  # Conferma il completamento dell'installazione Helm.
  echo -e "\033[32mINSTALLAZIONE OAUTH2-PROXY AVVENUTA CON SUCCESSO\033[0m"

  # Seleziona la versione edge della CLI Linkerd da installare.
  export LINKERD2_VERSION=edge-26.10.1
  # Scarica ed esegue lo script ufficiale di installazione della CLI.
  curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
  # Assicura che il file di configurazione della shell esista.
  touch "$HOME/.bashrc"
  # Evita di aggiungere più volte lo stesso percorso al PATH delle shell future.
  if ! grep -Fqx 'export PATH="$HOME/.linkerd2/bin:$PATH"' "$HOME/.bashrc"; then
    # Registra il percorso in .bashrc per le sessioni successive.
    printf '\n%s\n' 'export PATH="$HOME/.linkerd2/bin:$PATH"' >> "$HOME/.bashrc"
  fi

  # Controlla se il controller d'iniezione Linkerd è già installato.
  injector=$(minikube -p "$PROFILE" kubectl -- -n linkerd get deployment/linkerd-proxy-injector --ignore-not-found -o name)
  # Installa Gateway API e Linkerd soltanto se il controller non è presente.
  if [[ -z $injector ]]; then
    # Applica le definizioni standard Gateway API richieste da Linkerd.
    minikube -p "$PROFILE" kubectl -- apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
    # Verifica i prerequisiti del cluster prima di installare il control plane.
    linkerd --context "$PROFILE" check --pre
    # Installa nel cluster le CustomResourceDefinition di Linkerd.
    linkerd --context "$PROFILE" install --crds | minikube -p "$PROFILE" kubectl -- apply -f -
    # Installa il control plane Linkerd nel cluster Minikube.
    linkerd --context "$PROFILE" install | minikube -p "$PROFILE" kubectl -- apply -f -
  fi
  # Attende fino a cinque minuti che Linkerd risulti operativo.
  linkerd --context "$PROFILE" check --wait 5m

  # Verifica se è già presente il deployment delle metriche di Linkerd Viz.
  viz=$(minikube -p "$PROFILE" kubectl -- -n linkerd-viz get deployment/metrics-api --ignore-not-found -o name)
  # Installa Linkerd Viz solo quando non risulta già installato.
  if [[ -z $viz ]]; then
    linkerd --context "$PROFILE" viz install | minikube -p "$PROFILE" kubectl -- apply -f -
  fi
  # Conferma il completamento dell'installazione di Linkerd e Viz.
  echo -e "\033[32mINSTALLAZIONE LINKERD AVVENUTA CON SUCCESSO\033[0m"
else
  # In modalità solo-Keycloak verifica comunque lo stato del control plane.
  linkerd --context "$PROFILE" check --wait 5m
fi

# Legge il nome del Service headless associato al StatefulSet PostgreSQL.
servizio_headless=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "statefulset/$PG" -o jsonpath='{.spec.serviceName}')
# Marca la porta 5432 come protocollo opaco per il proxy Linkerd.
minikube -p "$PROFILE" kubectl -- -n "$NS" annotate "service/$PG" config.linkerd.io/opaque-ports=5432 --overwrite
# Se il Service headless ha un nome diverso, aggiunge la stessa annotazione anche a quello.
if [[ -n $servizio_headless && $servizio_headless != "$PG" ]]; then
  minikube -p "$PROFILE" kubectl -- -n "$NS" annotate "service/$servizio_headless" config.linkerd.io/opaque-ports=5432 --overwrite
fi

# Prepara le regole per PostgreSQL e Keycloak; nella modalità completa aggiunge anche Apache.
politiche=("$PG statefulset/$KC" "$KC deployment/traefik")
# Include la policy Apache soltanto nel flusso d'installazione completo.
if [[ $MODE != --solo-keycloak ]]; then
  politiche+=("mio-apache deployment/traefik")
fi
# Esamina una alla volta le policy e i rispettivi workload sorgente.
for voce in "${politiche[@]}"; do
  # Divide la coppia in nome della policy e risorsa sorgente.
  read -r policy sorgente <<< "$voce"
  # Recupera i tipi di traffico gestiti dalla policy, se presente.
  tipi=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "networkpolicy/$policy" --ignore-not-found -o jsonpath='{.spec.policyTypes[*]}')
  # Interviene soltanto sulle policy che isolano traffico in ingresso.
  if [[ " $tipi " == *' Ingress '* ]]; then
    # Legge il selettore dei pod protetti dalla policy.
    dst=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "networkpolicy/$policy" -o jsonpath='{.spec.podSelector}')
    # Legge il selettore dei pod sorgente autorizzati.
    src=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "$sorgente" -o jsonpath='{.spec.selector}')
    # Rifiuta selettori assenti o vuoti, che non consentirebbero una regola mirata.
    if [[ -z $dst || $dst == '{}' || -z $src || $src == '{}' ]]; then
      # Spiega che la porta del proxy non verrà aperta senza selettori validi.
      echo "Selettore mancante per $policy o $sorgente: non apro la porta 4143." >&2
      # Termina con errore per evitare un risultato incompleto.
      exit 1
    fi
    # Applica la regola di rete che consente solo il traffico proxy selezionato.
    minikube -p "$PROFILE" kubectl -- -n "$NS" apply -f - <<YAML
# Versione API Kubernetes delle NetworkPolicy.
apiVersion: networking.k8s.io/v1
# Tipo di risorsa da applicare.
kind: NetworkPolicy
# Nome della policy aggiuntiva e namespace di destinazione.
metadata:
  name: ${policy}-ingresso-linkerd
  namespace: ${NS}
# Definisce i pod destinatari e le connessioni consentite.
spec:
  # Riutilizza il selettore della policy che protegge i pod applicativi.
  podSelector: ${dst}
  # Indica che la regola filtra le connessioni in ingresso.
  policyTypes: [Ingress]
  # Elenca le regole d'ingresso da aggiungere.
  ingress:
  # Limita l'origine delle connessioni autorizzate.
    - from:
      # Selettore dei pod sorgente definiti dal workload richiesto.
        - podSelector: ${src}
      # Limita l'accesso alla porta inbound del proxy Linkerd.
      ports:
      # Consente TCP sulla sola porta 4143 del proxy.
        - {protocol: TCP, port: 4143}
YAML
  fi
# Termina la scansione delle policy richieste.
done

# Legge la generazione corrente di PostgreSQL prima di modificare il template.
prima=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "statefulset/$PG" -o jsonpath='{.metadata.generation}')
# Imposta l'iniezione Linkerd e dichiara opaca la porta PostgreSQL 5432 nel template.
dopo=$(minikube -p "$PROFILE" kubectl -- -n "$NS" patch "statefulset/$PG" --type=merge \
  -p '{"spec":{"template":{"metadata":{"annotations":{"linkerd.io/inject":"enabled","config.linkerd.io/opaque-ports":"5432"}}}}}' \
  -o jsonpath='{.metadata.generation}')
# Se il patch non cambia la generazione, controlla se il pod esistente è stato iniettato.
if [[ $prima == "$dopo" ]]; then
  # Elenca i container applicativi e init container del pod PostgreSQL.
  nomi=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "pod/${PG}-0" --ignore-not-found \
    -o go-template='{{range .spec.containers}}{{.name}} {{end}}{{range .spec.initContainers}}{{.name}} {{end}}')
  # Riavvia lo StatefulSet se il pod esiste ma non contiene il proxy Linkerd.
  if [[ -n $nomi && " $nomi " != *' linkerd-proxy '* ]]; then
    minikube -p "$PROFILE" kubectl -- -n "$NS" rollout restart "statefulset/$PG"
  fi
fi
# Attende il completamento del rollout di PostgreSQL.
minikube -p "$PROFILE" kubectl -- -n "$NS" rollout status "statefulset/$PG" --timeout="${ROLLOUT_TIMEOUT:-10m}"
# Rilegge i container del pod dopo il rollout per verificarne l'iniezione.
nomi=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "pod/${PG}-0" --ignore-not-found \
  -o go-template='{{range .spec.containers}}{{.name}} {{end}}{{range .spec.initContainers}}{{.name}} {{end}}')
# Fallisce se il webhook non ha aggiunto il proxy Linkerd al pod PostgreSQL.
if [[ " $nomi " != *' linkerd-proxy '* ]]; then
  # Indica la causa e suggerisce la modalità di diagnosi.
  echo "Il Pod ${PG}-0 non contiene linkerd-proxy. Controlla il webhook con --diagnosi." >&2
  # Interrompe prima dei controlli e dell'iniezione di Keycloak.
  exit 1
fi
# Verifica che PostgreSQL risponda sulla porta locale attesa dal container.
minikube -p "$PROFILE" kubectl -- -n "$NS" exec "${PG}-0" -c postgresql -- pg_isready -h 127.0.0.1 -p 5432 -U admin -d keycloak_db
# Conferma che PostgreSQL sia pronto e in mesh.
echo -e "\033[32mINIEZIONE DI POSTGRESS IN LINKERD AVVENUTA CON SUCCESSO\033[0m"

# Memorizza la generazione corrente di Keycloak prima di applicare le annotazioni.
prima=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "statefulset/$KC" -o jsonpath='{.metadata.generation}')
# Abilita il proxy Linkerd e il proxy-await nel template dei pod Keycloak.
dopo=$(minikube -p "$PROFILE" kubectl -- -n "$NS" patch "statefulset/$KC" --type=merge \
  -p '{"spec":{"template":{"metadata":{"annotations":{"linkerd.io/inject":"enabled","config.linkerd.io/proxy-await":"enabled"}}}}}' \
  -o jsonpath='{.metadata.generation}')
# Se il patch non modifica il template, controlla il pod attualmente in esecuzione.
if [[ $prima == "$dopo" ]]; then
  # Elenca i container applicativi e init container del pod Keycloak.
  nomi=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "pod/${KC}-0" --ignore-not-found \
    -o go-template='{{range .spec.containers}}{{.name}} {{end}}{{range .spec.initContainers}}{{.name}} {{end}}')
  # Riavvia lo StatefulSet se il pod esistente è privo del proxy.
  if [[ -n $nomi && " $nomi " != *' linkerd-proxy '* ]]; then
    minikube -p "$PROFILE" kubectl -- -n "$NS" rollout restart "statefulset/$KC"
  fi
fi
# Attende che Keycloak completi il rollout.
minikube -p "$PROFILE" kubectl -- -n "$NS" rollout status "statefulset/$KC" --timeout="${ROLLOUT_TIMEOUT:-10m}"
# Rilegge i container del pod Keycloak dopo il rollout.
nomi=$(minikube -p "$PROFILE" kubectl -- -n "$NS" get "pod/${KC}-0" --ignore-not-found \
  -o go-template='{{range .spec.containers}}{{.name}} {{end}}{{range .spec.initContainers}}{{.name}} {{end}}')
# Fallisce se il proxy non è presente nel pod Keycloak.
if [[ " $nomi " != *' linkerd-proxy '* ]]; then
  # Suggerisce la diagnosi per indagare il webhook d'iniezione.
  echo "Il Pod ${KC}-0 non contiene linkerd-proxy. Controlla il webhook con --diagnosi." >&2
  # Evita di dichiarare completato il mesh di Keycloak.
  exit 1
fi
# Mostra i pod PostgreSQL e Keycloak dopo aver verificato entrambi i proxy.
minikube -p "$PROFILE" kubectl -- -n "$NS" get pod "${PG}-0" "${KC}-0"
# Conferma che Keycloak e la dipendenza PostgreSQL sono stati iniettati.
echo -e "\033[32mINIEZIONE DI KEYCLOACK IN LINKERD AVVENUTA CON SUCCESSO\033[0m"

# La modalità ridotta termina dopo la configurazione di Keycloak e PostgreSQL.
if [[ $MODE == --solo-keycloak ]]; then
  exit 0
fi

# Inietta Linkerd negli altri workload dell'applicazione, uno alla volta.
for risorsa in deployment/traefik deployment/mio-oauth2-oauth2-proxy deployment/mio-apache statefulset/mio-mariadb; do
  # Aggiorna il template del workload per abilitare l'iniezione automatica.
  minikube -p "$PROFILE" kubectl -- -n "$NS" patch "$risorsa" --type=merge \
    -p '{"spec":{"template":{"metadata":{"annotations":{"linkerd.io/inject":"enabled"}}}}}'
  # Attende che i nuovi pod del workload diventino disponibili.
  minikube -p "$PROFILE" kubectl -- -n "$NS" rollout status "$risorsa" --timeout="${ROLLOUT_TIMEOUT:-10m}"
  # Stampa il messaggio specifico solo dopo il completamento del rollout.
  case "$risorsa" in
    # Conferma l'iniezione del proxy nel Deployment Traefik.
    deployment/traefik)
      echo -e "\033[32mINIEZIONE DI TRAEFIK IN LINKERD AVVENUTA CON SUCCESSO\033[0m"
      ;;
    # Conferma l'iniezione nel Deployment OAuth2 Proxy.
    deployment/mio-oauth2-oauth2-proxy)
      echo -e "\033[32mINIEZIONE DI OAUTH2-PROXY IN LINKERD AVVENUTA CON SUCCESSO\033[0m"
      ;;
    # Conferma l'iniezione nel Deployment Apache.
    deployment/mio-apache)
      echo -e "\033[32mINIEZIONE DI APACHE IN LINKERD AVVENUTA CON SUCCESSO\033[0m"
      ;;
    # Conferma l'iniezione nello StatefulSet MariaDB.
    statefulset/mio-mariadb)
      echo -e "\033[32mINIEZIONE DI MARIA-DB IN LINKERD AVVENUTA CON SUCCESSO\033[0m"
      ;;
  esac
done
# Esegue il controllo finale dei proxy Linkerd nel namespace dell'applicazione.
linkerd --context "$PROFILE" check --proxy --namespace "$NS" --wait 5m
