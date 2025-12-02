import logging, socket, signal, sys
from flask import Flask, request, jsonify

logging.basicConfig(
    format="%(created)f - %(levelname)s - %(message)s",
    level=logging.DEBUG
)

app = Flask(__name__)

@app.route('/', methods=['POST'])
def check_value():
    logging.debug(f"Received request with body: {request.get_json()}\n\n")
    hostnames = request.get_json().get('hostnames', [])
    hostnames.append(socket.gethostname())
    logging.debug(f"Current hostnames <{hostnames}>")
    return jsonify(hostnames=hostnames)

def shutdown_server():
    logging.info("Shutting down server gracefully...")
    sys.exit(0)

if __name__ == '__main__':
    # Register the SIGTERM handler
    signal.signal(signal.SIGTERM, lambda x, y: shutdown_server())

    app.run(host='0.0.0.0', port=8080)