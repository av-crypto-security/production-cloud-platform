import json
import os
import time

import pika
import psycopg2
from prometheus_client import Counter, start_http_server


POSTGRES_HOST = os.getenv("POSTGRES_HOST")
POSTGRES_DB = os.getenv("POSTGRES_DB")
POSTGRES_USER = os.getenv("POSTGRES_USER")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.getenv("RABBITMQ_USER")
RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD")

RABBITMQ_EXCHANGE = os.getenv(
    "RABBITMQ_EXCHANGE",
    "telemetry"
)
RABBITMQ_QUEUE = os.getenv(
    "RABBITMQ_QUEUE",
    "telemetry.measurements"
)
RABBITMQ_ROUTING_KEY = os.getenv(
    "RABBITMQ_ROUTING_KEY",
    "measurement"
)


while True:
    try:
        conn = psycopg2.connect(
            host=POSTGRES_HOST,
            database=POSTGRES_DB,
            user=POSTGRES_USER,
            password=POSTGRES_PASSWORD
        )
        break

    except Exception as exc:
        print(
            f"Waiting for PostgreSQL: {exc}",
            flush=True
        )
        time.sleep(5)


start_http_server(8001)

processed_measurements = Counter(
    "processed_measurements_total",
    "Total processed measurements"
)

rabbitmq_messages_processed = Counter(
    "rabbitmq_messages_processed_total",
    "Total RabbitMQ messages successfully processed"
)

rabbitmq_processing_failures = Counter(
    "rabbitmq_processing_failures_total",
    "Total RabbitMQ message processing failures"
)


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


rabbitmq_connection = create_rabbitmq_connection()
channel = rabbitmq_connection.channel()

channel.exchange_declare(
    exchange=RABBITMQ_EXCHANGE,
    exchange_type="direct",
    durable=True
)

channel.queue_declare(
    queue=RABBITMQ_QUEUE,
    durable=True
)

channel.queue_bind(
    exchange=RABBITMQ_EXCHANGE,
    queue=RABBITMQ_QUEUE,
    routing_key=RABBITMQ_ROUTING_KEY
)

channel.basic_qos(prefetch_count=1)


def process_measurement(measurement):
    cursor = conn.cursor()

    try:
        bridge_id = measurement["bridge_id"]
        timestamp = measurement["timestamp"]
        temperature = measurement["temperature"]
        humidity = measurement["humidity"]
        vibration = measurement["vibration"]
        tilt = measurement["tilt"]

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

        cursor.execute(
            """
            INSERT INTO measurements
            (
                bridge_id,
                timestamp,
                temperature,
                humidity,
                vibration,
                tilt,
                processed
            )
            VALUES (%s,%s,%s,%s,%s,%s,TRUE)
            """,
            (
                bridge_id,
                timestamp,
                temperature,
                humidity,
                vibration,
                tilt
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

        conn.commit()

    except Exception:
        conn.rollback()
        raise

    finally:
        cursor.close()


def callback(ch, method, properties, body):
    try:
        measurement = json.loads(body)

        process_measurement(measurement)

        processed_measurements.inc()
        rabbitmq_messages_processed.inc()

        ch.basic_ack(delivery_tag=method.delivery_tag)

        print(
            "Processed RabbitMQ measurement",
            flush=True
        )

    except Exception as exc:
        rabbitmq_processing_failures.inc()

        print(
            f"Processing failed: {exc}",
            flush=True
        )

        ch.basic_nack(
            delivery_tag=method.delivery_tag,
            requeue=True
        )


channel.basic_consume(
    queue=RABBITMQ_QUEUE,
    on_message_callback=callback,
    auto_ack=False
)

print(
    "Processing worker waiting for RabbitMQ messages",
    flush=True
)

channel.start_consuming()
