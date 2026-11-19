# Comparazione script: `installaProgettoDue.sh` e `installaProgettoDue-web.sh`

## Sintesi

Entrambi gli script eseguono la seconda fase del progetto:

1. chiedono il client secret di Keycloak;
2. ricreano il Secret Kubernetes `mio-oauth2-keycloak`;
3. generano `oauth2-keycloak-values.yaml`;
4. installano o aggiornano OAuth2 Proxy con Helm;
5. installano Linkerd;
6. inseriscono i sidecar Linkerd nei componenti del progetto.

`installaProgettoDue.sh` è la versione lineare e originale. `installaProgettoDue-web.sh`
è una versione più robusta pensata per questo ambiente: usa esplicitamente il
profilo Minikube, gestisce il reinstallatore e i rollout in modo controllato,
aggiunge modalità di ripristino e diagnosi e risolve il problema principale
dell'iniezione di Linkerd su PostgreSQL e Keycloak.

In caso di reinstallazione o recupero, lo script web è quello da preferire:

```bash
bash installaProgettoDue-web.sh
```

Il nome effettivamente presente nel progetto è `installaProgettoDue-web.sh`
(senza `azione`), come quello dell'altro script `installaProgettoDue.sh`.

## Tabella delle differenze principali

| Aspetto | `installaProgettoDue.sh` | `installaProgettoDue-web.sh` |
|---|---|---|
| `set` shell | `set -e` e `set -o pipefail` | `set -euo pipefail` |
| Profilo Minikube | Usa il profilo predefinito `minikube` | Legge `MINIKUBE_PROFILE`, con `minikube` come valore predefinito |
| Input secret | Secret mostrato durante la digitazione | Lettura silenziosa con `read -r -s` |
| Rinvio al Secret | Applicazione diretta | Applicazione diretta con le stesse chiavi |
| Modalità opzionali | Nessuna | `--solo-keycloak`, `--solo-policy-web`, `--diagnosi` |
| Helm | `helm upgrade --install` senza contesto esplicito | Imposta esplicitamente `--kube-context "$PROFILE"` |
| Linkerd | Installa sempre CRD, control plane e dashboard | Non ricrea un control plane già presente |
| Gateway API | Applica sempre l'installazione standard | La applica solo se manca l'injector Linkerd |
| Installazione dei componenti | Pipeline `get`, `inject`, `apply` | Patch mirata delle annotazioni del template, poi rollout |
| NetworkPolicy | Nessuna policy Linkerd aggiuntiva | Aggiunge permessi mirati per ingress proxy sulla porta `4143` |
| PostgreSQL | Iniezione di PostgreSQL, poi workaround su Keycloak successivo | PostgreSQL e Keycloak trattati in sequenza con porta SQL opaca |
| Recovery | Limitato: riapplica l'oggetto esportato | Apre il Pod e verifica la presenza di `linkerd-proxy` |
| Diagnosi | Nessuna modalità dedicata | Diagnostica pod, log, EndpointSlice, policy ed eventi |

## 1. Protezione e opzioni della shell

Il vecchio script usa:

```bash
set -e
set -o pipefail
```

La versione web usa invece:

```bash
set -euo pipefail
```

- `-e` interrompe lo script al primo errore.
- `-o pipefail` considera fallita una pipeline se anche un comando intermedio
  termina con errore.
- `-u` fa terminare lo script se viene usata una variabile non definita.
- `-o pipefail` evita che gli errori nascosti nelle pipeline vengano ignorati.

Il nuovo script può inoltre essere eseguito con:

```bash
bash installaProgettoDue-web.sh --solo-keycloak
bash installaProgettoDue-web.sh --solo-policy-web
bash installaProgettoDue-web.sh --diagnosi
```

Le modalità sono alternative alla seconda fase completa:

- `--solo-keycloak` controlla Linkerd e applica solo la riparazione di
  PostgreSQL/Keycloak;
- `--solo-policy-web` crea solo le due NetworkPolicy per il traffico web verso
  Keycloak e Apache;
- `--diagnosi` esegue esclusivamente operazioni di lettura per capire lo stato
  dell'infrastruttura.

Più di un argomento o un'opzione sconosciuta producono un errore di uso.

## 2. Selezione del profilo Minikube

La versione originale usa sempre il profilo predefinito tramite comandi del tipo:

```bash
minikube ip
minikube kubectl -- ...
```

La versione web determina il profilo con:

```bash
PROFILE=${MINIKUBE_PROFILE:-minikube}
```

In questo modo è possibile usare un profilo diverso senza modificare lo script:

```bash
MINIKUBE_PROFILE=mio-profilo bash installaProgettoDue-web.sh
```

Sono poi definite due funzioni abbreviate:

- `mk` esegue i comandi Minikube sul profilo selezionato;
- `k` esegue `kubectl` nel namespace `progetto`;
- `ld` esegue Linkerd usando il contesto corretto.

Ciò evita che Secret, URL issuer, Helm e Linkerd parlino a profili diversi.

## 3. Creazione del Secret OAuth

La parte iniziale è sostanzialmente equivalente:

- viene richiesta la `client secret` salvata al passaggio precedente;
- viene generato un cookie secret casuale con `openssl`;
- viene ricavato l'indirizzo IP di Minikube;
- viene ricavata la NodePort HTTP di Traefik;
- viene costruito l'issuer:

```text
http://<IP-MINIKUBE>:<TRAEFIK-NODEPORT>/realms/progetto
```

- viene creato o aggiornato il Secret `mio-oauth2-keycloak`;
- viene generato `oauth2-keycloak-values.yaml`;
- viene installato o aggiornato OAuth2 Proxy.

La differenza più visibile è nel prompt:

- lo script originale usa `read -r -p` e lascia visibile il valore digitato;
- lo script web usa `read -r -s -p`, quindi nasconde il client secret.

La versione web dichiara inoltre esplicitamente il contesto Helm:

```bash
--kube-context "$PROFILE"
```

Questo è importante quando esistono più cluster o profili nel computer.

## 4. Installazione di Linkerd

Entrambi gli script installano:

- Gateway API;
- i CRD di Linkerd;
- il control plane Linkerd;
- Linkerd Viz.

La differenza principale è il controllo dell'infrastruttura già esistente.

Lo script originale esegue sempre:

```bash
linkerd install --crds
linkerd install
linkerd viz install
```

La versione web verifica prima se esistono:

- il deployment `linkerd-proxy-injector`;
- il deployment `metrics-api` di Linkerd Viz.

Se esistono, non rigenera il control plane né i certificati già installati.
Questo evita una reinstallazione distruttiva durante il recupero di una
configurazione parzialmente applicata.

La versione web non usa inoltre una `LINKERD2_VERSION` per reinstallare
componenti già presenti. La CLI viene comunque scaricata o aggiornata e aggiunta
al `PATH`, mentre il control plane esistente viene mantenuto.

## 5. Installazione di PostgreSQL e Keycloak

Lo script originale inietta Linkerd con questa sequenza:

1. esegue `kubectl get` dello StatefulSet;
2. passa l'oggetto YAML a `linkerd inject`;
3. riapplica l'intero oggetto;
4. riavvia il rollout;
5. applica poi l'annotazione di esclusione della porta `5432` a Keycloak.

La versione web adotta un approccio diverso:

- individua il Service headless PostgreSQL;
- annota quel Service e il suo headless Service con
  `config.linkerd.io/opaque-ports=5432`;
- permette le sole connessioni Linkerd necessarie;
- applica l'annotazione Linkerd direttamente al template dello StatefulSet;
- attende la ricreazione dei Pod;
- verifica che PostgreSQL risponda con `pg_isready`;
- inietta poi Keycloak.

Nel caso del database PostgreSQL viene usata:

```text
config.linkerd.io/opaque-ports: "5432"
```

Questa configurazione serve perché il traffico PostgreSQL non è HTTP. Si evita
che Linkerd lo interpreti come traffico HTTP mentre Keycloak deve mantenere una
connessione persistente al database.

Per Keycloak viene inoltre usata:

```text
linkerd.io/inject: enabled
config.linkerd.io/proxy-await: enabled
```

`proxy-await` permette al Pod di attendere la piena disponibilità del proxy
prima di avviare il processo applicativo. È utile per evitare errori di avvio
quando il sidecar non è ancora pronto.

La verifica finale controlla anche che i Pod `mio-keycloak-postgresql-0` e
`mio-keycloak-0` contengano il container `linkerd-proxy`.

## 6. NetworkPolicy e porta 4143

La versione originale non crea policy aggiuntive per consentire il proxy
Linkerd. La versione web contiene la funzione `consenti_proxy`, che controlla
prima se esiste già una NetworkPolicy d'ingresso sui Pod interessati.

Il comportamento è volutamente conservativo:

- se il Pod non è già isolato da una NetworkPolicy d'ingresso, non viene creato
  un isolamento nuovo;
- se esiste già una policy d'ingresso, viene aggiunta una seconda policy mirata;
- la policy consente il traffico verso la porta `4143` del proxy Linkerd.

Questa porta è la porta inbound usata dal sidecar per ricevere il traffico
rimandato dal mesh.

La seconda fase completa aggiunge i permessi per:

1. Traefik verso Keycloak;
2. Traefik verso Apache.

La modalità `--solo-policy-web` esegue solo questi due aggiornamenti.

## 7. Metodo di injection e rollout

La funzione principale della versione web è `mesh_rollout`.

La versione originale esporta normalmente l'intero Deployment o StatefulSet
con `kubectl get`, lo modifica tramite `linkerd inject` e lo riapplica.
Questo può sovrascrivere campi gestiti da Helm o modifiche esterne.

La versione web modifica invece solo il template del Pod:

```json
spec.template.metadata.annotations
```

Per una risorsa con `RollingUpdate`, la modifica del template produce
automaticamente un nuovo rollout dei Pod.

La funzione controlla anche il caso di recupero:

- legge la generazione prima della patch;
- legge la generazione dopo la patch;
- se la generazione non cambia ma il Pod non ha ancora il proxy, riavvia
  la risorsa;
- attende la fine del rollout;
- verifica la presenza del container `linkerd-proxy`.

Ciò rende lo script adatto anche quando il rollout è stato avviato ma il Pod
precedente è rimasto attivo o il webhook non aveva ancora iniettato il sidecar.

## 8. Ordine di installazione e rollout

La versione originale inietta i componenti in questo ordine:

1. Apache;
2. OAuth2 Proxy;
3. Traefik;
4. MariaDB;
5. PostgreSQL;
6. Keycloak.

La versione web cambia la sequenza operativa:

1. PostgreSQL;
2. Keycloak;
3. i client HTTP Traefik, OAuth2 Proxy e Apache;
4. MariaDB.

PostgreSQL viene trattato per primo perché Keycloak dipende dal database.
Inoltre la porta `5432` viene marcata come opaca prima dell'iniezione di
PostgreSQL e Keycloak.

Il rollout dei componenti web avviene con:

```text
Traefik
OAuth2 Proxy
Apache
MariaDB
```

Il timeout predefinito è di dieci minuti per ciascun rollout, ma può essere
modificato con la variabile d'ambiente `ROLLOUT_TIMEOUT`.

Esempio:

```bash
ROLLOUT_TIMEOUT=15m bash installaProgettoDue-web.sh
```

## 9. Controlli finali

Lo script originale esegue controlli generali Linkerd con `linkerd check`,
ma non controlla sempre in modo esplicito che tutti i sidecar siano presenti
nei pod applicativi.

La versione web termina con:

```bash
ld check --proxy --namespace "$NS" --wait 5m
```

Questo verifica anche i proxy Linkerd nel namespace `progetto`, con attesa fino
a cinque minuti.

Le modalità `--solo-keycloak` e `--solo-policy-web` sono pensate per essere
eseguite dopo il primo tentativo di installazione, mentre `--diagnosi` mostra
lo stato senza modificare risorse.

## 10. Modalità diagnostica

`installaProgettoDue-web.sh --diagnosi` mostra:

- l'injector Linkerd nel namespace `linkerd`;
- gli StatefulSet Keycloak e PostgreSQL;
- i container dei Pod `mio-keycloak-0` e `mio-keycloak-postgresql-0`;
- l'EndpointSlice del database;
- tutte le NetworkPolicy del namespace;
- gli ultimi 50 log di Keycloak, PostgreSQL e dei rispettivi proxy;
- il log precedente di Keycloak, se disponibile;
- gli ultimi eventi Kubernetes di tipo `Warning`.

È utile per distinguere:

- Pod non iniettato;
- proxy presente ma Pod non pronto;
- Keycloak in crash loop;
- PostgreSQL non raggiungibile;
- problema delle NetworkPolicy;
- problema dell'injector Linkerd;
- problema di configurazione OIDC.

La diagnosi non modifica il cluster e può essere eseguita anche quando il
rollout completo è già fallito.

## Quale script usare

Usare `installaProgettoDue.sh` solo per riprodurre esattamente il procedimento
lineare originale oppure per confrontarlo con la soluzione web.

Usare `installaProgettoDue-web.sh` per:

- una nuova installazione sulla configurazione attuale;
- il recupero dopo un'installazione parziale;
- un cluster Minikube con profilo diverso da `minikube`;
- il debug dei Pod Keycloak/PostgreSQL;
- l'applicazione delle sole policy web;
- il ripristino del mesh senza reinstallare un control plane Linkerd esistente.
