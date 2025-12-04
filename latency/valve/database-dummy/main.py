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
    "photo.database.upload": {              # expected type in the request
        "type": "photo.database.new",       # response type for that event request
        "source": "photo-db-source",
    },
    "info.database.upload": {
        "type": "info.database.new",
        "source": "info-db-source",
    },
    "info.database.verification": {
        "type": "info.database.result",
        "source": "info-db-source",
    },
    "info.database.client": {
        "type": "info.database.resultClient",
        "source": "info-db-source",
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
