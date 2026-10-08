# agent-sandbox-boilerplate

Environnement de test pour sandboxer un agent de code. 
Tout son trafic HTTP passe par un proxy MITM.
L'objectif est de modifier des requêtes à la volée avant qu'elles ne partent vers le LLM (body, header...)

## Architecture

```
+-------------+        +-----------+        +--------------+
| asb-sandbox | -----> | asb-mitm  | -----> | asb-fake-llm |
|   (agent)   |  HTTP  | (proxy)   |  HTTP  |  (echo HTTP) |
+-------------+        +-----------+        +--------------+
```

- `sandbox` : alpine + curl. Réseau `internal`, sans accès Internet.
  `http_proxy` pointe vers `mitm`.
- `mitm` : mitmproxy (`mitmdump`). Seul pont entre les deux réseaux.
  Charge les addons de `mitm/addons/`.
- `fake-llm` : serveur Python qui renvoie le body reçu et l'affiche dans ses logs.

## Prérequis

- podman
- podman-compose
- just

## Commandes

| Commande             | Rôle                                                 |
| -------------------- | ---------------------------------------------------- |
| `just` / `just test` | Lance tous les tests (monte la stack si besoin)      |
| `just up`            | Construit et démarre la stack                        |
| `just down`          | Arrête la stack                                      |

Exemple, envoyer une requête depuis la sandbox :

```
podman exec asb-sandbox curl -s --data "bonjour" http://fake-llm:8080/
```

## Écrire une règle (addon)

1. Copier `mitm/addons/noop.py` dans un nouveau fichier de `mitm/addons/`.
2. Modifier la fonction `request(flow)`
3. `podman restart asb-mitm` pour charger le nouveau fichier.
