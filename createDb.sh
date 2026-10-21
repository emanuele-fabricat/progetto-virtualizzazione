#!/bin/bash
minikube kubectl -- exec -i -n progetto mio-mariadb-0 -- \
mariadb -u root -pAdmin1234! <<EOF
CREATE DATABASE IF NOT EXISTS prova;
USE prova;
CREATE TABLE IF NOT EXISTS citta (
	id INT PRIMARY KEY AUTO_INCREMENT,
	nome VARCHAR(100)
);
INSERT INTO citta(nome)
VALUES
	('ciola araldi'),
	('cesena'),
	('gattolino');
EOF

