                                from flask import Flask, request, jsonify
import logging

app = Flask(__name__)

logging.basicConfig(
	level=logging.INFO,
	format="%(asctime)s %(levelname)s %(message)s",
)

logger = logging.getLogger(__name__)


@app.get("/health")
def health():
	return jsonify({"status": "ok"}), 200


@app.post("/alerts")
def receive_alerts():
	payload = request.get_json(silent=True) or {}

	status = payload.get("status", "unknown")
	alerts = payload.get("alerts", [])

	if not alerts:
		logger.info(
			"ALERTMANAGER NOTIFICATION status=%s alerts=0",
			status,
		)
		return jsonify({"received": 0}), 200

	for alert in alerts:
		labels = alert.get("labels", {})

		alertname = labels.get("alertname", "unknown")
		severity = labels.get("severity", "unknown")
		namespace = labels.get("namespace", "unknown")

		logger.info(
			"ALERTMANAGER NOTIFICATION "
			"status=%s alertname=%s severity=%s namespace=%s",
			status,
			alertname,
			severity,
			namespace,
		)

	return jsonify({"received": len(alerts)}), 200


if __name__ == "__main__":
	app.run(host="0.0.0.0", port=8080)
