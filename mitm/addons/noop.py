# Addon modèle : ne transforme rien, logge chaque requête
# Copier ce fichier pour écrire une nouvelle règle
import logging

from mitmproxy import http


def request(flow: http.HTTPFlow) -> None:
    logging.info(f"noop addon: {flow.request.path}")
