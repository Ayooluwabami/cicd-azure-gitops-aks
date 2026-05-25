from flask import Flask, jsonify
import os

app = Flask(__name__)

VERSION = os.getenv("APP_VERSION", "1.0.0")


@app.route("/")
def home():
    return jsonify({"service": "python-app", "status": "running", "version": VERSION})


@app.route("/health")
def health():
    return jsonify({"status": "healthy"})


@app.route("/api/data")
def data():
    return jsonify(
        {
            "service": "python-app",
            "message": "Hello from the Python microservice!",
            "version": VERSION,
        }
    )


if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
