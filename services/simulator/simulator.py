import random
from datetime import datetime, UTC
import requests
import time

def generate_measurement():
	return {
		"bridge_id": f"M-{random.randint(1, 50)}",
		"timestamp": datetime.now(UTC).isoformat(),
		"temperature": round(random.uniform(20, 35), 2),
		"humidity": round(random.uniform(40, 80), 2),
		"vibration": round(random.uniform(0.05, 0.30), 2),
		"tilt": round(random.uniform(0.0, 1.0), 2),
	}

def inject_anomaly(data):
	if random.random() < 0.01:
		print("Anomaly generated!")
		metric = random.choice(
			["temperature", "humidity", "vibration", "tilt"]
		)

		if metric == "temperature":
			data[metric] = round(random.uniform(80, 120), 2)
		elif metric == "humidity":
			data[metric] = round(random.uniform(95, 100), 2)
		elif metric == "vibration":
			data[metric] = round(random.uniform(2, 5), 2)
		elif metric == "tilt":
			data[metric] = round(random.uniform(5, 15), 2)

	return data

def send_measurement(data):
	response = requests.post(
		"http://ingestion-api:8000/measurements",
		json=data,
		timeout=5,
	)
	return response.status_code

def main():
	while True:
		data = generate_measurement()
		data = inject_anomaly(data)

		print(data)

		try:
			status = send_measurement(data)
			print(f"HTTP {status}")

		except Exception as e:
			print(f"ERROR: {e}")

		time.sleep(5)

if __name__ == "__main__":
	main()
