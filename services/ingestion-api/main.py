import json
import os
from datetime import datetime

import pika
from fastapi import FastAPI
from pydantic import BaseModel
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI()

Instrumentator().instrument(app).expose(app)


RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.getenv("RABBITMQ_USER")
RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD")

RABBITMQ_EXCHANGE = os.getenv("RABBITMQ_EXCHANGE", "telemetry")
RABBITMQ_QUEUE = os.getenv(
    "RABBITMQ_QUEUE",
    "telemetry.measurements"
)
RABBITMQ_ROUTING_KEY = os.getenv(
    "RABBITMQ_ROUTING_KEY",
    "measurement"
)


class Measurement(BaseModel):
    bridge_id: str
    timestamp: datetime
    temperature: float
    humidity: float
    vibration: float
    tilt: float


def create_rabbitmq_connection():
    credentials = pika.PlainCredentials(
        RABBITMQ_USER,
        RABBITMQ_PASSWORD
    )

    parameters = pika.ConnectionParameters(
        host=RABBITMQ_HOST,
        port=RABBITMQ_PORT,
        credentials=credentials
    )

    return pika.BlockingConnection(parameters)


rabbitmq_connection = None
rabbitmq_channel = None


def get_rabbitmq_channel():
    global rabbitmq_connection
    global rabbitmq_channel

    if (
        rabbitmq_connection is None
        or rabbitmq_connection.is_closed
    ):
        rabbitmq_connection = create_rabbitmq_connection()
        rabbitmq_channel = rabbitmq_connection.channel()

        rabbitmq_channel.confirm_delivery()

        rabbitmq_channel.exchange_declare(
            exchange=RABBITMQ_EXCHANGE,
            exchange_type="direct",
            durable=True
        )

        rabbitmq_channel.queue_declare(
            queue=RABBITMQ_QUEUE,
            durable=True
        )

        rabbitmq_channel.queue_bind(
            exchange=RABBITMQ_EXCHANGE,
            queue=RABBITMQ_QUEUE,
            routing_key=RABBITMQ_ROUTING_KEY
        )

    return rabbitmq_channel


@app.post("/measurements", status_code=202)
def receive_measurement(data: Measurement):

    channel = get_rabbitmq_channel()

    payload = data.model_dump(mode="json")

    channel.basic_publish(
        exchange=RABBITMQ_EXCHANGE,
        routing_key=RABBITMQ_ROUTING_KEY,
        body=json.dumps(payload),
        properties=pika.BasicProperties(
            delivery_mode=2,
            content_type="application/json"
        )
    )

    return {
        "status": "accepted"
    }


@app.get("/health")
def health():
    return {
        "status": "ok"
    }
