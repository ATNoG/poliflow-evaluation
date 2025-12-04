import uuid, random, string, requests, os, logging, binascii
from flask import Flask, request, jsonify

logging.basicConfig(
    format="%(created)f - %(levelname)s - %(message)s",
    level=logging.DEBUG
)

app = Flask(__name__)

def rand_hex_32():
    b = os.urandom(32)
    return binascii.hexlify(b).decode()

K_SINK = os.getenv("K_SINK")
HEADERS_REMOVE = ("Ce-Id", "Ce-Specversion", "Ce-Type", "Ce-Source", "Content-Type", "Host")
PATH = {
    "Seq": [
        {
            "ProtectedName": "entry-point" + "-" + rand_hex_32(),
            "ProtectedType": "event"
        }
    ]
}

@app.route("/", methods=["POST"])
def forward_to_broker():
    event = request.get_json()
    ce_id = str(uuid.uuid4())
    logging.debug(f"Received request with id <{ce_id}>")
    headers = {
        "Ce-Id": ce_id,
        "Ce-Specversion": "1.0",
        "Ce-Type": "http.request.received",
        "Ce-Source": "http-event-source",
        "Content-Type": "application/json",
        **{k: v for k, v in request.headers.items() if k not in HEADERS_REMOVE}
    }

    tag_suffix = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
    new_key = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
    event[f"tags-{tag_suffix}"] = new_key
    event[new_key] = PATH

    response = requests.post(K_SINK, json={"data": event, "headers": dict(request.headers)}, headers=headers)
    return {"forwarded-response": response.text if response.status_code < 500 else None, "id": ce_id}, response.status_code

if __name__ == "__main__":
    if not K_SINK:
        logging.warning("Missing required environment variables: K_SINK")
    app.run(host="0.0.0.0", port=8080)
