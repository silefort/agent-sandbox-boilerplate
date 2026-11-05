#!/usr/bin/env bash
# Tests de bout en bout, exécutés sur l'hôte
# Format : commentaires Given / When / Then
# Pour tester depuis un container : exec_container <container> <commande...>
# Chaque test fait exit 1 en cas d'échec
set -uo pipefail

CONTAINERS=(asb-sandbox asb-mitm asb-fake-llm)

# Exécute une commande dans un container
# Usage : exec_container asb-sandbox curl -sS http://fake-llm:8080/
exec_container() {
    local container=$1
    shift
    podman exec "$container" "$@"
}

# Vrai si les 3 containers de la stack tournent déjà
stack_running() {
    local container
    for container in "${CONTAINERS[@]}"; do
        [ "$(podman inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" = "true" ] || return 1
    done
    return 0
}

# Attend que la chaîne sandbox -> mitm -> fake-llm réponde
wait_stack_ready() {
    local i body
    for i in $(seq 1 50); do
        body=$(exec_container asb-sandbox curl -s --max-time 1 --data ping http://fake-llm:8080/ 2>/dev/null)
        [ "$body" = "ping" ] && return 0
        sleep 0.2
    done
    return 1
}

echo "--- always true"
# Given
# When
resultat=true
# Then
[ "$resultat" = true ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- la stack compose fonctionne"
# Given la stack est peut-être déjà démarrée
if stack_running && [ "${ASB_FORCE_UP:-0}" != "1" ]; then
    # When elle tourne déjà : inutile de relancer podman-compose (lent)
    echo "OK (stack déjà démarrée, ASB_FORCE_UP=1 pour forcer un rebuild)"
else
    # When on monte la stack une seule fois pour toute la suite
    output=$(just up 2>&1); code_retour=$?
    # Then la commande réussit (sinon on affiche sa sortie)
    [ "$code_retour" = 0 ] || { echo "$output"; echo "FAIL"; exit 1; }
    # Then la stack répond avant d'enchaîner les tests (évite les faux échecs)
    wait_stack_ready || { echo "FAIL : la stack ne répond pas après 'just up'"; exit 1; }
    echo "OK"
fi

echo "--- le container asb-fake-llm est running"
# Given la stack est up
# When on inspecte le container fake-llm
running=$(podman inspect -f '{{.State.Running}}' asb-fake-llm)
# Then le container fake-llm tourne
[ "$running" = "true" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- fake-llm renvoie ce qu'on lui envoie"
# Given la stack est up
# When on envoie ping à fake-llm depuis son propre container
body=$(exec_container asb-fake-llm curl -s --data ping http://localhost:8080/)
# Then fake-llm renvoie ping
[ "$body" = "ping" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- fake-llm affiche le body reçu dans ses logs"
# Given la stack est up
# When on envoie un body unique à fake-llm
body="print-test-$RANDOM"
exec_container asb-fake-llm curl -s --data "$body" http://localhost:8080/ > /dev/null
# Then le body apparaît dans les logs de fake-llm
logs=$(podman logs asb-fake-llm 2>&1)
echo "$logs" | grep "$body" > /dev/null && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- le container asb-sandbox est running"
# Given la stack est up
# When on inspecte le container sandbox
running=$(podman inspect -f '{{.State.Running}}' asb-sandbox)
# Then le container sandbox tourne
[ "$running" = "true" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- sandbox n'atteint pas fake-llm en direct"
# Given la stack est up
# When sandbox envoie ping à fake-llm sans proxy
code_retour=$(exec_container asb-sandbox curl -s --noproxy '*' --max-time 1 --data ping http://fake-llm:8080/ > /dev/null; echo $?)
# Then la requête échoue
[ "$code_retour" != 0 ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- sandbox n'a pas d'accès Internet"
# Given la stack est up
# When sandbox contacte une IP publique sans proxy (1.1.1.1, sans DNS)
code_retour=$(exec_container asb-sandbox curl -s --noproxy '*' --max-time 1 http://1.1.1.1/ > /dev/null; echo $?)
# Then la requête échoue
[ "$code_retour" != 0 ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- le container asb-mitm est running"
# Given la stack est up
# When on inspecte le container mitm
running=$(podman inspect -f '{{.State.Running}}' asb-mitm)
# Then le container mitm tourne
[ "$running" = "true" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- sandbox atteint fake-llm via le proxy"
# Given la stack est up
# When sandbox envoie ping à fake-llm (proxy via http_proxy)
body=$(exec_container asb-sandbox curl -s --max-time 3 --data ping http://fake-llm:8080/)
# Then fake-llm renvoie ping
[ "$body" = "ping" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- la requête de sandbox apparaît dans les logs de mitm"
# Given la stack est up
# When sandbox envoie une requête sur un chemin unique
path="/mitm-test-$RANDOM"
exec_container asb-sandbox curl -s --max-time 3 --data ping "http://fake-llm:8080$path" > /dev/null
# Then le chemin apparaît dans les logs de mitm
logs=$(podman logs asb-mitm 2>&1)
echo "$logs" | grep "$path" > /dev/null && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- l'addon noop de mitm est exécuté sur chaque requête"
# Given la stack est up
# When sandbox envoie une requête sur un chemin unique
path="/noop-test-$RANDOM"
exec_container asb-sandbox curl -s --max-time 3 --data ping "http://fake-llm:8080$path" > /dev/null
# Then l'addon noop a loggé ce chemin dans les logs de mitm
logs=$(podman logs asb-mitm 2>&1)
echo "$logs" | grep "noop addon: $path" > /dev/null && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- mitm charge tous les addons de mitm/addons"
# Given la stack est up
# When on lit les logs de mitm
logs=$(podman logs asb-mitm 2>&1)
# Then chaque fichier .py du dossier a été chargé
for addon in mitm/addons/*.py; do
    echo "$logs" | grep "Loading script /addons/$(basename "$addon")" > /dev/null || { echo "FAIL : $addon non chargé"; exit 1; }
done
echo "OK"

echo "--- l'addon obfuscate_keywords de mitm est exécuté sur chaque requête"
# Given la stack est up
# When sandbox envoie une requête sur un chemin unique
path="/obfuscate_keywords-test-$RANDOM"
exec_container asb-sandbox curl -s --max-time 3 --data ping "http://fake-llm:8080$path" > /dev/null
# Then l'addon obfuscate_keywords a loggé ce chemin dans les logs de mitm
logs=$(podman logs asb-mitm 2>&1)
echo "$logs" | grep "obfuscate_keywords addon: $path" > /dev/null && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- fake-llm ne reçoit pas foo"
# Given la stack est up
# When sandbox envoie foo à fake-llm
name=foo-$RANDOM
exec_container asb-sandbox curl -s --max-time 3 --data $name http://fake-llm:8080/ -o /dev/null
# Then body ne contient pas foo
logs=$(podman logs asb-fake-llm 2>&1)
(echo "$logs" | grep "$name" > /dev/null) ; code_retour=$?
[ "$code_retour" != 0 ] && echo "OK" || { echo "FAIL"; exit 1; }


echo "--- mitm change foo en bar"
# Given la stack est up
# When sandbox envoie foo à fake-llm
body=$(exec_container asb-sandbox curl -s --max-time 3 --data foo http://fake-llm:8080/)
# Then body contient bar
[ "$body" = "bar" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- mitm change je suis foo en je suis bar"
# Given la stack est up
# When sandbox envoie foo à fake-llm
rand=$RANDOM
body=$(exec_container asb-sandbox curl -s --max-time 3 --data "je suis foo $rand" http://fake-llm:8080/)
# Then body contient bar
[ "$body" = "je suis bar $rand" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "--- mitm obfusque les requêtes en fonction des clés: valeurs de test.ini"
# Given la stack est up
# When sandbox envoie les clés, elles doivent être remplacées par leur valeur
FICHIER="tests/test.ini"

while IFS='=' read -r cle valeur; do
    body=$(exec_container asb-sandbox curl -s --max-time 3 --data "je suis $cle" http://fake-llm:8080/)
    # Then body contient la valeur obfusquée
    [ "$body" = "je suis $valeur" ] && echo "OK" || { echo "FAIL"; exit 1; }

done < "$FICHIER"

echo "--- mitm obfusque une IP en jeton IP_OBFUSQUEE_n"
# Given la stack est up
# When sandbox envoie une IP à fake-llm
body=$(exec_container asb-sandbox curl -s --max-time 3 --data "serveur 192.168.1.10" http://fake-llm:8080/)
# Then body contient un jeton et plus l'IP
[ "$body" = "serveur IP_OBFUSQUEE_1" ] && echo "OK" || { echo "FAIL"; exit 1; }

echo "Tous les tests sont OK"
