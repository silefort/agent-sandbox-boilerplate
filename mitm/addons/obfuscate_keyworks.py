import logging, yaml

from mitmproxy import http

def request(flow: http.HTTPFlow) -> None:
    logging.info(f"obfuscate_keyworks addon: {flow.request.path}")
    
    with open('/addons/conf.yaml', 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    
    for cle in config:
        flow.request.text = flow.request.text.replace(cle, config[cle])
