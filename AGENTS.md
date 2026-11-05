# AGENTS.md

Contexte destiné aux agents (humains ou IA) qui travaillent sur ce dépôt.

## But du projet

`agent-sandbox-boilerplate` est un environnement de test pour **sandboxer un agent de code** :
tout son trafic HTTP passe par un proxy MITM, qui peut réécrire les requêtes à la volée
(body, headers…) avant qu'elles n'atteignent le LLM. Le LLM est simulé par un serveur echo.

## Conventions

- Code, docs, commentaires et messages de commit en **français**.
- Commits au format Conventional Commits, **sur une seule ligne**
  (ex. `perf: monter la stack une seule fois dans les tests`).
- Développement en **TDD** : écrire d'abord les tests, les voir échouer,
  puis développer la fonctionnalité jusqu'à les faire passer.

## Architecture

```
asb-sandbox (alpine+curl)  →  asb-mitm (mitmproxy)  →  asb-fake-llm (echo Python)
   réseau internal              2 réseaux              réseau upstream
```

- Réseau `internal` (`internal: true`) : aucune passerelle vers l'extérieur → la sandbox
  n'a **pas d'accès Internet** et ne peut joindre que les containers du même réseau.
- Réseau `upstream` : réseau de fake-llm, séparé de la sandbox.
- **mitm est le seul pont** entre les deux réseaux (il est sur `internal` + `upstream`).
  C'est ce qui rend le passage par le proxy obligatoire.

## Composants

| Chemin | Rôle |
| --- | --- |
| `compose.yaml` | Définition des 3 services et des 2 réseaux. |
| `sandbox/` | `alpine` + `curl`, `sleep infinity`. `http_proxy`/`HTTP_PROXY` → `http://mitm:8080`. |
| `mitm/` | Image mitmproxy + `pyyaml`. Lance `mitmdump` avec un `-s` par fichier `.py` de `/addons`. |
| `mitm/addons/` | Règles de réécriture, montées en volume `:ro,Z`. |
| `mitm/addons/noop.py` | Addon modèle : logge chaque requête, ne transforme rien. |
| `mitm/addons/obfuscate_keyworks.py` | Remplace les occurrences du body selon `conf.yaml`. |
| `mitm/addons/conf.yaml` | Paires `clé: valeur` utilisées par l'addon de remplacement. |
| `fake-llm/` | Serveur Python `HTTPServer` : logge le body POST reçu et le renvoie tel quel. |
| `tests/tests.sh` | Tests bout-en-bout, exécutés **depuis l'hôte**. |
| `tests/test.ini` | Jeu de paires `clé=valeur` utilisé par les tests. |
| `justfile` | Raccourcis de commandes (`just`, `just up`, `just down`, …). |

## Flux d'une requête

1. `curl` dans la sandbox lit `http_proxy` et contacte `mitm:8080`.
2. `mitmdump` exécute les addons chargés (ordre alphabétique de fichier) :
   `noop` logge le chemin, `obfuscate_keyworks` remplace les occurrences dans le body.
3. La requête modifiée part vers `fake-llm:8080`, qui logge le body **modifié** et le renvoie.
4. `curl` reçoit donc la version obfusquée.

## Écrire / modifier une règle (addon)

- **Modifier** un fichier `.py` existant dans `mitm/addons/` : rechargement automatique,
  aucun rebuild ni restart.
- **Ajouter** un nouveau fichier `.py` : `podman restart asb-mitm` (le volume est monté,
  pas besoin de rebuild).
- Point d'entrée : une fonction `request(flow: http.HTTPFlow)` (hook mitmproxy).
  Copier `noop.py` comme modèle.
- `PYTHONUNBUFFERED=1` est indispensable sur mitm : les tests lisent les logs
  immédiatement après la requête.

## Commandes

| Commande | Effet |
| --- | --- |
| `just` / `just test` | Lance `tests/tests.sh` (monte la stack si besoin) |
| `just up` | `podman-compose up -d --build` |
| `just down` | Arrête la stack |
| `just clean` | Arrête la stack et supprime les volumes |
| `just logs [service]` | Logs suivis (tous les services si vide) |
| `just shell [service]` | Shell dans un container (`sandbox` par défaut) |

Exemple manuel :

```
podman exec asb-sandbox curl -s --data "bonjour" http://fake-llm:8080/
```

## Tests

- `tests/tests.sh` s'exécute **sur l'hôte**, avec `podman` et `just`, depuis la racine du dépôt.
- Convention : chaque test est introduit par `echo "--- nom"` puis des commentaires
  `# Given`, `# When`, `# Then`. En cas d'échec : afficher `FAIL` et `exit 1`.
- Les tests vérifient notamment : montée de la stack, containers running, echo de fake-llm,
  isolation réseau (pas d'accès direct à fake-llm ni à Internet), passage effectif par le proxy,
  chargement de **tous** les `.py` de `mitm/addons`, et application des remplacements
  de `conf.yaml` / `test.ini`.
- Avant d'ajouter un test, vérifier qu'il échoue bien si la fonctionnalité est absente.
- **Performance** : `podman-compose up` est lent, donc `tests.sh` ne monte la stack qu'**une
  seule fois**, au début. Si les 3 containers tournent déjà, `just up` est court-circuité
  (utiliser `ASB_FORCE_UP=1 just test` pour forcer un rebuild). Ne pas réintroduire de
  `just up` dans les tests suivants.
- Après une montée, `wait_stack_ready` attend que le chemin sandbox → mitm → fake-llm réponde
  avant d'enchaîner, pour éviter les faux échecs liés au démarrage.

## Pièges connus

- `entrypoint` de mitm : `$$` dans `compose.yaml` = `$` littéral (sinon compose interprète
  `$f` comme une variable). L'entrypoint de l'image mitmproxy est contourné car son `gosu`
  échoue en podman rootless.
- `obfuscate_keyworks.py` relit `conf.yaml` **à chaque requête** : modifiable sans restart.
- `flow.request.text` décode le body en texte → fragile sur du binaire / non-UTF-8.
- Seul le hook `request` existe : obfuscation **unidirectionnelle** (rien sur la réponse).
- La réécriture s'applique à **toutes** les requêtes proxifiées, pas uniquement au LLM.
- Pas de HTTPS pour l'instant : mitmdump ne voit que le HTTP clair.

## Pistes (TODO.md)

Obfuscation bidirectionnelle des noms, support HTTPS, vrai LLM avec streaming,
obfuscation des IP par regex, wrapper CLI (Python ou Go).

## Documents complémentaires pour l'agent

Lire aussi ces fichiers (dossier `custom_agents/`, ignoré par git) :

- [custom_agents/CUSTOM_AGENTS.md](custom_agents/CUSTOM_AGENTS.md)

## Préférences de communication

### Mode de travail : pair programming

- On travaille en **pair programming** : ne pas implémenter seul de bout en bout.
- Avancer par **petits incréments**, validés un par un avec moi.
- Raccourcir les boucles de feedback : montrer tôt, montrer souvent.
- Avant un changement non trivial, proposer l'approche et attendre mon accord.
- Après chaque étape (test rouge, test vert, refacto), faire un point court.

### Style

Quand tu me réponds, réponds-moi en ASD-STE100 :

Phrases courtes uniquement (8-10 mots max).
voix active ;
une idée par phrase ;
aucun paragraphe d'introduction ni de conclusion.
