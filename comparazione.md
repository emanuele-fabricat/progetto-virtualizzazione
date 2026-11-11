# Comparazione YAML: Ubuntu e Debian

## Come leggere i rimandi

Confronto dei 15 file omonimi nelle cartelle [YamlUbuntu](./YamlUbuntu) e
[YamlDebian](./YamlDebian). Ogni riferimento `L<n>` apre il file alla riga
indicata. I rimandi sono forniti per entrambi i sistemi, così puoi confrontare
direttamente le righe corrispondenti.

Nei manifest Kubernetes alcune righe sono configurazione voluta (per esempio
`image`, `type`, `nodePort` e le variabili d'ambiente); altre sono assegnate
automaticamente dal cluster (per esempio `creationTimestamp`, `resourceVersion`,
`uid`, `clusterIP` e `status`). Il secondo gruppo normalmente cambia perché i
manifest provengono da cluster diversi.

## Tabella riassuntiva

| File | Differenza principale |
|---|---|
| `deployments-mio-apache.yaml` | Tag immagine Apache: `latest` su Ubuntu, versione Debian fissata su Debian. |
| `deployments-mio-oauth2-oauth2-proxy.yaml` | URL issuer diverso; `--set-xauthrequest=true` solo su Ubuntu; riavvio annotato solo su Debian. |
| `deployments-traefik.yaml` | Traefik `v3.7.17` / chart `42.3.0` su Ubuntu contro `v3.7.13` / chart `41.6.1` su Debian. |
| `services-mio-apache.yaml` | Configurazione uguale; cambia l'indirizzo ClusterIP assegnato ai due Service. |
| `services-mio-keycloak-headless.yaml` | Configurazione uguale; variano solo i metadati generati dal cluster. |
| `services-mio-keycloak-postgresql-hl.yaml` | Configurazione uguale; variano solo i metadati generati dal cluster. |
| `services-mio-keycloak-postgresql.yaml` | Configurazione uguale; cambia il ClusterIP. |
| `services-mio-keycloak.yaml` | Ubuntu espone Keycloak con NodePort `31119`; Debian lo espone solo come ClusterIP. |
| `services-mio-mariadb-headless.yaml` | Chart MariaDB `28.1.6` su Ubuntu contro `28.1.1` su Debian; configurazione di rete uguale. |
| `services-mio-mariadb.yaml` | Come sopra: versioni chart diverse, rete uguale a parte il ClusterIP. |
| `services-mio-oauth2-oauth2-proxy.yaml` | Configurazione uguale; cambia il ClusterIP. |
| `services-traefik.yaml` | Versione chart diversa e NodePort HTTP/HTTPS differenti. |
| `statefulsets-mio-keycloak-postgresql.yaml` | Immagine e configurazione effettiva uguali; cambiano valori runtime generati dal cluster. |
| `statefulsets-mio-keycloak.yaml` | Immagine e configurazione effettiva uguali; cambiano valori runtime generati dal cluster. |
| `statefulsets-mio-mariadb.yaml` | Cambiano chart, immagine, database, utente applicativo e secret. |

## Analisi dettagliata, file per file

### 1. `deployments-mio-apache.yaml`

Riferimenti: [Ubuntu, riga 65](./YamlUbuntu/deployments-mio-apache.yaml#L65)
e [Debian, riga 65](./YamlDebian/deployments-mio-apache.yaml#L65).

- **Ubuntu:** `docker.io/bitnamilegacy/apache:latest`.
- **Debian:** `docker.io/bitnamilegacy/apache:2.4.65-debian-12-r2`.
- Entrambi i container avviano Apache, ma `latest` è un tag mobile: può puntare
  a un'immagine aggiornata senza cambiare il manifest. Il tag Debian identifica
  invece una release precisa e quindi rende i deploy più riproducibili.
- Lo stesso container immagine viene specificato anche nell'init container che
  prepara i log: [Ubuntu, riga 148](./YamlUbuntu/deployments-mio-apache.yaml#L148)
  e [Debian, riga 148](./YamlDebian/deployments-mio-apache.yaml#L148).
- Chart, porte, probe e risorse non mostrano differenze funzionali nel confronto.
  Timestamp, generazione e resource version sono invece valori del cluster:
  [Ubuntu, righe 10-11](./YamlUbuntu/deployments-mio-apache.yaml#L10)
  / [Debian, righe 10-11](./YamlDebian/deployments-mio-apache.yaml#L10).

### 2. `deployments-mio-oauth2-oauth2-proxy.yaml`

Riferimenti: issuer [Ubuntu, riga 63](./YamlUbuntu/deployments-mio-oauth2-oauth2-proxy.yaml#L63)
e [Debian, riga 64](./YamlDebian/deployments-mio-oauth2-oauth2-proxy.yaml#L64);
opzione X-Auth-Request [Ubuntu, riga 67](./YamlUbuntu/deployments-mio-oauth2-oauth2-proxy.yaml#L67);
annotazione [Debian, riga 45](./YamlDebian/deployments-mio-oauth2-oauth2-proxy.yaml#L45).

- **Issuer OIDC:** Ubuntu punta a `http://192.168.49.2:31119/realms/progetto`;
  Debian punta a `http://192.168.49.2:32622/realms/progetto`. L'issuer è
  l'indirizzo da cui OAuth2 Proxy recupera la configurazione OIDC e con cui
  valida le informazioni del provider. Host, porta e percorso devono essere
  raggiungibili dal proxy e coerenti con l'URL pubblicato da Keycloak.
- Le porte corrispondono a modalità di esposizione differenti: `31119` è il
  NodePort del Service Keycloak Ubuntu ([Service Ubuntu, riga 31](./YamlUbuntu/services-mio-keycloak.yaml#L31));
  `32622` è il NodePort HTTP di Traefik Debian
  ([Service Traefik Debian, riga 29](./YamlDebian/services-traefik.yaml#L29)).
  Nel caso Debian il traffico verso l'issuer passa quindi attraverso Traefik,
  mentre nel manifest Ubuntu punta direttamente al NodePort di Keycloak.
- **Header X-Auth-Request:** Ubuntu imposta `--set-xauthrequest=true`; Debian
  non presenta questa opzione. Quando attiva, OAuth2 Proxy produce gli header
  `X-Auth-Request-*` per i componenti a valle che ne fanno uso. Se ingress o
  applicazioni si aspettano questi header, la differenza può cambiare
  l'integrazione dell'autenticazione.
- Debian aggiunge `kubectl.kubernetes.io/restartedAt` al pod template; è
  normalmente un'annotazione usata per forzare un nuovo rollout. Ubuntu non
  riporta questa annotazione nel manifest.
- Immagine OAuth2 Proxy e versione chart sono uguali: immagine alla
  [riga 87 Ubuntu](./YamlUbuntu/deployments-mio-oauth2-oauth2-proxy.yaml#L87)
  e [riga 87 Debian](./YamlDebian/deployments-mio-oauth2-oauth2-proxy.yaml#L87).

### 3. `deployments-traefik.yaml`

Riferimenti: immagine [Ubuntu, riga 80](./YamlUbuntu/deployments-traefik.yaml#L80)
e [Debian, riga 78](./YamlDebian/deployments-traefik.yaml#L78);
chart [Ubuntu, riga 17](./YamlUbuntu/deployments-traefik.yaml#L17)
e [Debian, riga 16](./YamlDebian/deployments-traefik.yaml#L16).

- Ubuntu esegue `traefik:v3.7.17` con chart `traefik-42.3.0`.
- Debian esegue `traefik:v3.7.13` con chart `traefik-41.6.1`.
- Quindi differiscono sia il programma Traefik sia il pacchetto Helm che ne
  genera la configurazione. Il chart può includere valori predefiniti e template
  diversi; questa differenza può incidere sul comportamento anche se molti
  argomenti e porte del Deployment appaiono uguali.
- L'immagine del container è il dato operativo da controllare per la versione
  effettivamente avviata; la versione chart identifica invece la release dei
  template Kubernetes installati.

### 4. `services-mio-apache.yaml`

Riferimenti: ClusterIP [Ubuntu, riga 19](./YamlUbuntu/services-mio-apache.yaml#L19)
e [Debian, riga 19](./YamlDebian/services-mio-apache.yaml#L19);
porte [Ubuntu, righe 28-34](./YamlUbuntu/services-mio-apache.yaml#L28)
e [Debian, righe 28-34](./YamlDebian/services-mio-apache.yaml#L28).

- Ubuntu ha `clusterIP: 10.109.84.110`; Debian ha `clusterIP: 10.111.81.167`.
  Kubernetes assegna questi indirizzi all'interno di ciascun cluster, perciò è
  normale che siano diversi e non vanno copiati da un cluster all'altro.
- Porte HTTP `80` e HTTPS `443`, target port e selector sono uguali: la
  funzionalità del Service è la stessa.
- Cambiano anche timestamp e resource version, che sono metadati del cluster,
  non parametri da configurare manualmente.

### 5. `services-mio-keycloak-headless.yaml`

Riferimenti: ClusterIP headless [Ubuntu, riga 21](./YamlUbuntu/services-mio-keycloak-headless.yaml#L21)
e [Debian, riga 21](./YamlDebian/services-mio-keycloak-headless.yaml#L21);
porta [Ubuntu, riga 30](./YamlUbuntu/services-mio-keycloak-headless.yaml#L30)
e [Debian, riga 30](./YamlDebian/services-mio-keycloak-headless.yaml#L30).

- Entrambi hanno `clusterIP: None`: è un Service headless, che non riceve un
  IP virtuale unico e permette ai client DNS di risolvere direttamente gli
  endpoint dei pod.
- Porta HTTP `8080`, selettori e `publishNotReadyAddresses` coincidono.
- Le differenze di timestamp, resource version e UID sono dati generati
  separatamente nei due cluster, non differenze applicative.

### 6. `services-mio-keycloak-postgresql-hl.yaml`

Riferimenti: ClusterIP [Ubuntu, riga 20](./YamlUbuntu/services-mio-keycloak-postgresql-hl.yaml#L20)
e [Debian, riga 20](./YamlDebian/services-mio-keycloak-postgresql-hl.yaml#L20);
porta [Ubuntu, riga 29](./YamlUbuntu/services-mio-keycloak-postgresql-hl.yaml#L29)
e [Debian, riga 29](./YamlDebian/services-mio-keycloak-postgresql-hl.yaml#L29).

- Entrambi sono headless (`clusterIP: None`) e pubblicano PostgreSQL sulla
  porta `5432`.
- Target port, selector e pubblicazione degli indirizzi dei pod non pronti
  coincidono.
- Cambiano solo metadati generati dal cluster, come timestamp, resource version
  e UID.

### 7. `services-mio-keycloak-postgresql.yaml`

Riferimenti: ClusterIP [Ubuntu, riga 20](./YamlUbuntu/services-mio-keycloak-postgresql.yaml#L20)
e [Debian, riga 20](./YamlDebian/services-mio-keycloak-postgresql.yaml#L20);
porta [Ubuntu, riga 29](./YamlUbuntu/services-mio-keycloak-postgresql.yaml#L29)
e [Debian, riga 29](./YamlDebian/services-mio-keycloak-postgresql.yaml#L29).

- Ubuntu usa ClusterIP `10.102.50.138`; Debian usa `10.104.240.71`.
- Entrambi sono Service interni di tipo `ClusterIP`, sulla porta `5432`, con
  lo stesso target port e selector.
- Gli indirizzi diversi sono assegnati dai rispettivi cluster; non indicano
  una porta o un protocollo diverso.

### 8. `services-mio-keycloak.yaml`

Riferimenti: Service Ubuntu, [type riga 41](./YamlUbuntu/services-mio-keycloak.yaml#L41),
[nodePort riga 31](./YamlUbuntu/services-mio-keycloak.yaml#L31),
[ClusterIP riga 21](./YamlUbuntu/services-mio-keycloak.yaml#L21);
Service Debian, [type riga 39](./YamlDebian/services-mio-keycloak.yaml#L39),
[ClusterIP riga 21](./YamlDebian/services-mio-keycloak.yaml#L21).

- **Ubuntu:** `type: NodePort`, porta del Service `80` e porta esterna al nodo
  `31119`. Il servizio è raggiungibile dall'esterno del cluster tramite
  `IP-del-nodo:31119`.
- **Debian:** `type: ClusterIP`, porta `80`, senza `nodePort`. Il servizio è
  raggiungibile direttamente solo dall'interno del cluster, salvo esposizione
  tramite un altro componente (qui, per esempio, Traefik).
- Ubuntu dichiara anche `externalTrafficPolicy: Cluster`
  ([riga 24](./YamlUbuntu/services-mio-keycloak.yaml#L24)); Debian non ha quel
  campo perché il Service non è di tipo NodePort o LoadBalancer.
- Questa differenza è coerente con i due issuer OAuth2: Ubuntu usa
  `192.168.49.2:31119`; Debian usa `192.168.49.2:32622`, che corrisponde al
  NodePort HTTP di Traefik Debian. Verifica che la route Traefik esponga
  effettivamente il realm Keycloak all'URL configurato.

### 9. `services-mio-mariadb-headless.yaml`

Riferimenti: chart [Ubuntu, riga 14](./YamlUbuntu/services-mio-mariadb-headless.yaml#L14)
e [Debian, riga 14](./YamlDebian/services-mio-mariadb-headless.yaml#L14);
porta [Ubuntu, riga 29](./YamlUbuntu/services-mio-mariadb-headless.yaml#L29)
e [Debian, riga 29](./YamlDebian/services-mio-mariadb-headless.yaml#L29).

- Il Service Ubuntu riporta chart `mariadb-28.1.6`, Debian
  `mariadb-28.1.1`. È una differenza di versione del chart Helm, non della
  porta esposta dal Service.
- Entrambi sono headless (`clusterIP: None`) e pubblicano MariaDB sulla porta
  `3306`, con stesso target port e selettori.
- La versione del chart corrisponde a quella osservata nello StatefulSet
  MariaDB della rispettiva cartella.

### 10. `services-mio-mariadb.yaml`

Riferimenti: chart [Ubuntu, riga 15](./YamlUbuntu/services-mio-mariadb.yaml#L15)
e [Debian, riga 15](./YamlDebian/services-mio-mariadb.yaml#L15);
ClusterIP [Ubuntu, riga 21](./YamlUbuntu/services-mio-mariadb.yaml#L21)
e [Debian, riga 21](./YamlDebian/services-mio-mariadb.yaml#L21).

- La versione del chart è `28.1.6` su Ubuntu e `28.1.1` su Debian.
- Il Service pubblica la porta `3306` in entrambi i casi. Gli indirizzi
  ClusterIP sono diversi perché assegnati da cluster distinti.
- I selector individuano il pod MariaDB primario; il Service e la relativa
  connettività sono altrimenti equivalenti.

### 11. `services-mio-oauth2-oauth2-proxy.yaml`

Riferimenti: ClusterIP [Ubuntu, riga 22](./YamlUbuntu/services-mio-oauth2-oauth2-proxy.yaml#L22)
e [Debian, riga 22](./YamlDebian/services-mio-oauth2-oauth2-proxy.yaml#L22);
porte [Ubuntu, righe 32-39](./YamlUbuntu/services-mio-oauth2-oauth2-proxy.yaml#L32)
e [Debian, righe 32-39](./YamlDebian/services-mio-oauth2-oauth2-proxy.yaml#L32).

- Cambia il ClusterIP (`10.97.170.114` Ubuntu, `10.100.147.86` Debian), assegnato
  automaticamente dai rispettivi cluster.
- Le porte HTTP `80` e metriche `44180`, i target port e i selector coincidono.
  Non emerge una differenza di comportamento del Service.

### 12. `services-traefik.yaml`

Riferimenti: chart [Ubuntu, riga 13](./YamlUbuntu/services-traefik.yaml#L13)
e [Debian, riga 12](./YamlDebian/services-traefik.yaml#L12);
nodePort HTTP [Ubuntu, riga 30](./YamlUbuntu/services-traefik.yaml#L30)
e [Debian, riga 29](./YamlDebian/services-traefik.yaml#L29);
nodePort HTTPS [Ubuntu, riga 35](./YamlUbuntu/services-traefik.yaml#L35)
e [Debian, riga 34](./YamlDebian/services-traefik.yaml#L34).

- Il chart è `traefik-42.3.0` su Ubuntu e `traefik-41.6.1` su Debian.
- Entrambi i Service sono di tipo `LoadBalancer`; le porte del Service sono
  HTTP `80` e HTTPS `443`.
- Le porte assegnate sui nodi differiscono: Ubuntu usa `30125` (HTTP) e `32504`
  (HTTPS); Debian usa `32622` (HTTP) e `32720` (HTTPS). Se un client accede
  direttamente ai nodi, deve usare la coppia del cluster corrispondente.
- Anche `clusterIP` differisce, ma è un indirizzo interno assegnato
  automaticamente.

### 13. `statefulsets-mio-keycloak-postgresql.yaml`

Riferimenti: immagine [Ubuntu, riga 94](./YamlUbuntu/statefulsets-mio-keycloak-postgresql.yaml#L94)
e [Debian, riga 94](./YamlDebian/statefulsets-mio-keycloak-postgresql.yaml#L94);
metadati [Ubuntu, righe 9-10](./YamlUbuntu/statefulsets-mio-keycloak-postgresql.yaml#L9)
e [Debian, righe 9-10](./YamlDebian/statefulsets-mio-keycloak-postgresql.yaml#L9);
revisioni [Ubuntu, riga 208](./YamlUbuntu/statefulsets-mio-keycloak-postgresql.yaml#L208)
e [Debian, riga 208](./YamlDebian/statefulsets-mio-keycloak-postgresql.yaml#L208).

- Immagine PostgreSQL e chart `16.7.26` coincidono; anche le revisioni
  `currentRevision` e `updateRevision` riportate in fondo al file coincidono.
- Le righe di `creationTimestamp`, `generation` e `resourceVersion` differiscono
  perché descrivono oggetti e aggiornamenti registrati da cluster differenti.
  Non indicano, da sole, una diversa configurazione del database.

### 14. `statefulsets-mio-keycloak.yaml`

Riferimenti: immagine [Ubuntu, riga 74](./YamlUbuntu/statefulsets-mio-keycloak.yaml#L74)
e [Debian, riga 74](./YamlDebian/statefulsets-mio-keycloak.yaml#L74);
metadati [Ubuntu, righe 9-10](./YamlUbuntu/statefulsets-mio-keycloak.yaml#L9)
e [Debian, righe 9-10](./YamlDebian/statefulsets-mio-keycloak.yaml#L9);
revisioni [Ubuntu, riga 226](./YamlUbuntu/statefulsets-mio-keycloak.yaml#L226)
e [Debian, riga 226](./YamlDebian/statefulsets-mio-keycloak.yaml#L226).

- L'immagine Keycloak (`26.3.3-debian-12-r0`), chart (`25.2.0`) e configurazione
  del pod coincidono nel confronto.
- Anche i valori `currentRevision` e `updateRevision` coincidono. A differire
  sono soprattutto timestamp, generazione e resource version, che riflettono
  lo stato dei due cluster.

### 15. `statefulsets-mio-mariadb.yaml`

Riferimenti: chart [Ubuntu, riga 18](./YamlUbuntu/statefulsets-mio-mariadb.yaml#L18)
e [Debian, riga 18](./YamlDebian/statefulsets-mio-mariadb.yaml#L18);
variabili e database [Ubuntu, righe 67-73](./YamlUbuntu/statefulsets-mio-mariadb.yaml#L67)
e [Debian, righe 67-69](./YamlDebian/statefulsets-mio-mariadb.yaml#L67);
immagine [Ubuntu, riga 79](./YamlUbuntu/statefulsets-mio-mariadb.yaml#L79)
e [Debian, riga 75](./YamlDebian/statefulsets-mio-mariadb.yaml#L75);
secret [Ubuntu, righe 229-233](./YamlUbuntu/statefulsets-mio-mariadb.yaml#L229)
e [Debian, righe 225-227](./YamlDebian/statefulsets-mio-mariadb.yaml#L225).

- **Chart:** Ubuntu usa `mariadb-28.1.6`, Debian `mariadb-28.1.1`. Template e
  valori predefiniti possono quindi non essere identici.
- **Immagine:** Ubuntu usa `bitnamilegacy/mariadb:latest`; Debian usa
  `bitnami/mariadb:latest`. Oltre al namespace del registry, cambia quindi
  l'immagine sorgente. In entrambi i casi `latest` è un tag mobile, non una
  versione immutabile.
- **Database iniziale:** Ubuntu crea/usa `miodb`; Debian `my_database`. Le
  applicazioni che si collegano al database devono usare il nome previsto
  nell'ambiente corrispondente. Questi valori vengono usati in fase
  d'inizializzazione: un volume dati già popolato può conservare il database
  preesistente, quindi il solo cambio della variabile non rinomina i dati.
- **Utente applicativo:** Ubuntu dichiara `MARIADB_USER=admin` e indica
  `MARIADB_PASSWORD_FILE` per leggere la password da file. Debian non dichiara
  queste due variabili: dal manifest non risulta quindi la configurazione
  esplicita di quell'utente applicativo.
- **Secret montato:** Ubuntu monta due chiavi, `mariadb-root-password` e
  `mariadb-password`; Debian monta solo `mariadb-root-password`. La password
  root resta configurata in entrambi, mentre il secret della password
  dell'utente `admin` è presente solo su Ubuntu.
- **Checksum:** il valore `checksum/configuration` è diverso
  ([Ubuntu, riga 40](./YamlUbuntu/statefulsets-mio-mariadb.yaml#L40);
  [Debian, riga 40](./YamlDebian/statefulsets-mio-mariadb.yaml#L40)). È un hash
  della configurazione associata: varia quando varia il contenuto configurato
  e può essere usato per rilevare modifiche e riavviare i pod.
- Risorse, porta `3306`, probe, storage richiesto e modalità di esecuzione
  risultano sostanzialmente allineati; le differenze descritte sopra sono quelle
  che cambiano l'immagine e la configurazione dell'istanza/database.

## Conclusione

Le differenze funzionali più rilevanti riguardano il percorso di accesso a
Keycloak e OAuth2 Proxy, le versioni di Traefik, e la configurazione di
MariaDB (immagine, database, utente e secret). Gli altri Service hanno in
prevalenza configurazioni equivalenti, con indirizzi IP e metadati diversi
perché appartengono a cluster distinti.
