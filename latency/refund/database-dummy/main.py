import uuid
import requests, os, logging
from flask import Flask, request, jsonify, make_response
import socket

logging.basicConfig(
    format="%(created)f - %(levelname)s - %(message)s",
    level=logging.DEBUG
)

app = Flask(__name__)

EVENTS = {
    "order.database.get": {              # expected type in the request
        "type": "order.database.result",       # response type for that event request
        "source": "database-dummy",
    },
    "info.database.emitRefund": {
        "type": "info.database.result",
        "source": "database-dummy",
    },
}

@app.route("/", methods=["POST"])
def forward_to_broker(): 
    event_type = request.headers.get("ce-type")

    if event_type not in EVENTS:
        return {"message": "Event type not found"}, 404

    event = request.get_json()
    logging.debug(f"Received request with event: {event}")
    hostnames = event.get('hostnames', [])
    hostnames.append(socket.gethostname())
    event['hostnames'] = hostnames
    logging.debug(f"Current hostnames <{hostnames}>")

    ce_id = request.headers.get("ce-id")
    
    headers = {
        "Ce-Id": str(uuid.uuid4()),
        "Ce-Specversion": "1.0",
        "Ce-kogitoprocrefid": ce_id,
        "Ce-Type": EVENTS[event_type]["type"],
        "Ce-Source": EVENTS[event_type]["source"],
        "Content-Type": "application/json",
    }
    return event, 200, headers

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
