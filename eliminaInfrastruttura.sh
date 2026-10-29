#!/bin/bash

#Elimino minikube da qualsiasi punto del filesistem
minikube delete
sudo rm /usr/local/bin/minikube
rm -rf ~/.minikube
rm -rf ~/.kube

#Elimino helm da qualsiasi punto del filesistem
sudo rm /usr/local/bin/helm
rm -rf ~/.cache/helm
rm -rf ~/.config/helm
rm -rf ~/.local/share/helm

#Elimino Linkerd
sudo rm -f ~/.local/bin/linkerd
rm -rf ~/linkerd*


# Ferma docker
sudo systemctl stop docker
sudo systemctl stop docker.socket

# Rimuovi pacchetti
sudo apt purge -y docker.io

# Pulizia dipendenze
sudo apt autoremove -y

# Elimina dati docker
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd

# Elimina configurazioni utente
rm -rf ~/.docker

# Elimina gruppo docker (facoltativo)
sudo groupdel docker 2>/dev/null

# Aggiorna cache pacchetti
sudo apt clean

minikube version
helm version
docker --version


