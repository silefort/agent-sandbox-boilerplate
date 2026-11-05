import logging, re

from mitmproxy import http

IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")

# IP réelle -> jeton (mapping gardé en mémoire, stable pour une même IP)
jetons: dict[str, str] = {}

def jeton_pour(ip: str) -> str:
    if ip not in jetons:
        jetons[ip] = f"IP_OBFUSQUEE_{len(jetons) + 1}"
    return jetons[ip]

def request(flow: http.HTTPFlow) -> None:
    logging.info(f"obfuscate_ips addon: {flow.request.path}")
    flow.request.text = IPV4.sub(lambda m: jeton_pour(m.group(0)), flow.request.text)
