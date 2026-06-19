import os
import time
import psycopg2
from fastapi import FastAPI
from pydantic import BaseModel
from datetime import datetime

app = FastAPI()

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

class Measurement(BaseModel):
	bridge_id: str
	timestamp: datetime
	temperature: float
	humidity: float
	vibration: float
	tilt: float

@app.post("/measurements")
def recieve_measurement(data: Measurement):

	cursor.execute(
		"""
		INSERT INTO measurements
		(
			bridge_id,
			timestamp,
			temperature,
			humidity,
			vibration,
			tilt
		)
		VALUES (%s,%s,%s,%s,%s,%s)
		""",
		(
			data.bridge_id,
			data.timestamp,
			data.temperature,
			data.humidity,
			data.vibration,
			data.tilt
		)
	)
	
	conn.commit()

	return {
		"status": "accepted"
	}

@app.get("/health")
def health():
	return {
		"status": "ok"
	}
