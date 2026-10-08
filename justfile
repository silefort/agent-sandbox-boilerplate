# Agent sandbox - commandes de la stack

# Lance tous les tests (recette par défaut)
test:
    ./tests/tests.sh

# Démarre la stack
up:
    podman-compose up -d --build

# Arrête la stack
down:
    podman-compose down

# Arrête la stack et supprime les volumes
clean:
    podman-compose down -v

# Logs d'un service (ou de tous)
logs service="":
    podman-compose logs -f {{service}}

# Shell dans un container
shell service="sandbox":
    podman exec -it asb-{{service}} sh
