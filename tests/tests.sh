#!/usr/bin/env bash
# Tests de bout en bout, exécutés sur l'hôte
# Format : commentaires Given / When / Then
# Pour tester depuis un container : exec_container <container> <commande...>
# Chaque test fait exit 1 en cas d'échec
set -uo pipefail

# Exécute une commande dans un container
# Usage : exec_container asb-sandbox curl -sS http://fake-llm:8080/
exec_container() {
    local container=$1
    shift
    podman exec "$container" "$@"
}

echo "--- always true"
# Given
# When
resultat=true
# Then
[ "$resultat" = true ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- la stack compose fonctionne"
# Given
# When on monte la stack
output=$(just up 2>&1); code_retour=$?
# Then la commande réussit (sinon on affiche sa sortie)
[ "$code_retour" = 0 ] && echo "OK" || { echo "$output"; echo "FAIL"; exit 1; }

echo "--- le container asb-fake-llm est running"
# Given
just up > /dev/null 2>&1
# When on inspecte le container fake-llm
running=$(podman inspect -f '{{.State.Running}}' asb-fake-llm)
# Then le container fake-llm tourne
[ "$running" = "true" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- fake-llm renvoie ce qu'on lui envoie"
# Given la stack est up
just up > /dev/null 2>&1
# When on envoie ping à fake-llm depuis son propre container
body=$(exec_container asb-fake-llm curl -s --data ping http://localhost:8080/)
# Then fake-llm renvoie ping
[ "$body" = "ping" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- fake-llm affiche le body reçu dans ses logs"
# Given la stack est up
just up > /dev/null 2>&1
# When on envoie un body unique à fake-llm
body="print-test-$RANDOM"
exec_container asb-fake-llm curl -s --data "$body" http://localhost:8080/ > /dev/null
# Then le body apparaît dans les logs de fake-llm
logs=$(podman logs asb-fake-llm 2>&1)
echo "$logs" | grep "$body" > /dev/null && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- le container asb-sandbox est running"
# Given la stack est up
just up > /dev/null 2>&1
# When on inspecte le container sandbox
running=$(podman inspect -f '{{.State.Running}}' asb-sandbox)
# Then le container sandbox tourne
[ "$running" = "true" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- sandbox n'atteint pas fake-llm en direct"
# Given la stack est up
just up > /dev/null 2>&1
# When sandbox envoie ping à fake-llm sans proxy
code_retour=$(exec_container asb-sandbox curl -s --noproxy '*' --max-time 3 --data ping http://fake-llm:8080/ > /dev/null; echo $?)
# Then la requête échoue
[ "$code_retour" != 0 ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- sandbox n'a pas d'accès Internet"
# Given la stack est up
just up > /dev/null 2>&1
# When sandbox contacte une IP publique sans proxy (1.1.1.1, sans DNS)
code_retour=$(exec_container asb-sandbox curl -s --noproxy '*' --max-time 3 http://1.1.1.1/ > /dev/null; echo $?)
# Then la requête échoue
[ "$code_retour" != 0 ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- le container asb-mitm est running"
# Given la stack est up
just up > /dev/null 2>&1
# When on inspecte le container mitm
running=$(podman inspect -f '{{.State.Running}}' asb-mitm)
# Then le container mitm tourne
[ "$running" = "true" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- sandbox atteint fake-llm via le proxy"
# Given la stack est up
just up > /dev/null 2>&1
# When sandbox envoie ping à fake-llm (proxy via http_proxy)
body=$(exec_container asb-sandbox curl -s --max-time 3 --data ping http://fake-llm:8080/)
# Then fake-llm renvoie ping
[ "$body" = "ping" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- la requête de sandbox apparaît dans les logs de mitm"
# Given la stack est up
just up > /dev/null 2>&1
# When sandbox envoie une requête sur un chemin unique
path="/mitm-test-$RANDOM"
exec_container asb-sandbox curl -s --max-time 3 --data ping "http://fake-llm:8080$path" > /dev/null
# Then le chemin apparaît dans les logs de mitm
logs=$(podman logs asb-mitm 2>&1)
echo "$logs" | grep "$path" > /dev/null && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- l'addon noop de mitm est exécuté sur chaque requête"
# Given la stack est up
just up > /dev/null 2>&1
# When sandbox envoie une requête sur un chemin unique
path="/noop-test-$RANDOM"
exec_container asb-sandbox curl -s --max-time 3 --data ping "http://fake-llm:8080$path" > /dev/null
# Then l'addon noop a loggé ce chemin dans les logs de mitm
logs=$(podman logs asb-mitm 2>&1)
echo "$logs" | grep "noop addon: $path" > /dev/null && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- mitm charge tous les addons de mitm/addons"
# Given la stack est up
just up > /dev/null 2>&1
# When on lit les logs de mitm
logs=$(podman logs asb-mitm 2>&1)
# Then chaque fichier .py du dossier a été chargé
for addon in mitm/addons/*.py; do
    echo "$logs" | grep "Loading script /addons/$(basename "$addon")" > /dev/null || { echo "FAIL : $addon non chargé"; exit 1; }
done
echo "OK"

echo "Tous les tests sont OK"
