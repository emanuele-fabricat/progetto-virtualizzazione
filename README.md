# progetto-virtualizzazione

Creazione di un'infrastruttura multi-servizio con un service mesh che cifra le
comunicazioni tra i servizi.

1. Decomprimere la cartella e aprire una shell al suo interno.
2. Eseguire `installaProgettoUno.sh`.
3. Seguire le istruzioni di `settingKeycloak.txt`.
4. Tornare nella shell ed eseguire `installaProgettoDue.sh`.
5. Per provare l'applicazione, avviare `utilizzoSistema.sh` e aprire
   `http://localhost:8081` nel browser.

Lo script applica a Keycloak l'annotazione Linkerd
`config.linkerd.io/skip-outbound-ports: "5432"` prima di iniettare il sidecar:
in questo modo le connessioni PostgreSQL non vengono intercettate dal proxy
in uscita. Al termine, verificare che l'annotazione sia sul pod e che entrambi
i pod siano pronti:

```sh
minikube kubectl -- get pod mio-keycloak-0 mio-keycloak-postgresql-0 -n progetto \
  -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[*].ready,SKIP-DB-PROXY:.metadata.annotations.config\\.linkerd\\.io/skip-outbound-ports
```

Le differenze tra lo script originale `installaProgettoDue.sh` e la versione
aggiornata `installaProgettoDue-web.sh` sono descritte in
[comparazione-script.md](./comparazione-script.md).