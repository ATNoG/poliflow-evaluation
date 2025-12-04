import logging
from flask import Flask, request, jsonify
import socket

logging.basicConfig(
    format="%(created)f - %(levelname)s - %(message)s",
    level=logging.DEBUG
)

app = Flask(__name__)

@app.route('/', methods=['POST'])
def check_value():
    hostnames = request.get_json().get('hostnames', [])
    hostnames.append(socket.gethostname())
    logging.debug(f"Current hostnames <{hostnames}>")
    return jsonify(hostnames=hostnames)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
