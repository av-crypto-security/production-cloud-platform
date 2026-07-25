import os
import time
import psycopg2
from prometheus_client import Counter
from prometheus_client import start_http_server

while True:
	try:
		conn = psycopg2.connect(
			host=os.getenv("POSTGRES_HOST"),
			database=os.getenv("POSTGRES_DB"),
			user=os.getenv("POSTGRES_USER"),
			password=os.getenv("POSTGRES_PASSWORD")
		)
		break
	except Exception:
		print("Waiting for PostgreSQL...")
		time.sleep(5)

cursor = conn.cursor()

start_http_server(8001)

processed_measurements = Counter (
	"processed_measurements_total",
	"Total processed measurements"
)

while True:
	
	cursor.execute(
		"""
		SELECT
			id,
			bridge_id,
			timestamp,
			temperature,
			humidity,
			vibration,
			tilt
		FROM measurements
		WHERE processed = FALSE
		"""
	)
	measurements = cursor.fetchall()

	for measurement in measurements:
		measurement_id = measurement[0]
		bridge_id = measurement[1]
		timestamp = measurement[2]
		temperature = measurement[3]
		humidity = measurement[4]
		vibration = measurement[5]
		tilt = measurement[6]

		alerts = []

		if temperature > 80:
			alerts.append(
				(
					"HIGH_TEMPERATURE",
					"critical",
					f"Temperature={temperature}"
				)
			)

		if humidity > 95:
			alerts.append(
				(
					"HIGH_HUMIDITY",
					"warning",
					f"Humidity={humidity}"
				)
			)

		if vibration > 2:
			alerts.append(
				(
					"HIGH_VIBRATION",
					"critical",
					f"Vibration={vibration}"
				)
			)

		if tilt > 5:
			alerts.append(
				(
					"HIGH_TILT",
					"critical",
					f"Tilt={tilt}"
				)
			)

		for alert_type, severity, message in alerts:
			cursor.execute(
				"""
				INSERT INTO alerts
				(
					bridge_id,
					timestamp,
					alert_type,
					severity,
					message
				)
				VALUES (%s,%s,%s,%s,%s)
				""",
				(
					bridge_id,
					timestamp,
					alert_type,
					severity,
					message
				)
			)
		
		cursor.execute(
			"""
			UPDATE measurements
			SET processed = TRUE
			WHERE id = %s
			""",
			(measurement_id,)
		)
	
	conn.commit()

	print(
		f"Processed {len(measurements)} measurements"
	)

	processed_measurements.inc(len(measurements))
	
	time.sleep(10)
