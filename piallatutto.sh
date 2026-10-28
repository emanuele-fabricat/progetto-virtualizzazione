#!/bin/bash

#Elimino minikube da qualsiasi punto del filesistem
sudo rm /usr/local/bin/minikube
rm -rf ~/.minikube
rm -rf ~/.kube

#Elimino helm da qualsiasi punto del filesistem
sudo rm /usr/local/bin/helm
rm -rf ~/.cache/helm
rm -rf ~/.config/helm
rm -rf ~/.local/share/helm

minikube version
helm version