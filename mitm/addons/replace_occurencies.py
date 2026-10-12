# Addon modèle : ne transforme rien, logge chaque requête
# Copier ce fichier pour écrire une nouvelle règle
import logging

from mitmproxy import http


def request(flow: http.HTTPFlow) -> None:
    logging.info(f"replace_occurencies addon: {flow.request.path}")
    flow.request.text = flow.request.text.replace("foo", "bar")
