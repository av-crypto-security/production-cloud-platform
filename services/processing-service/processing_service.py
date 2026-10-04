import json
import os
import time

import pika
import psycopg2

from prometheus_client import Counter, start_http_server


# PostgreSQL configuration

POSTGRES_HOST = os.getenv("POSTGRES_HOST")
POSTGRES_DB = os.getenv("POSTGRES_DB")
POSTGRES_USER = os.getenv("POSTGRES_USER")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")


# RabbitMQ configuration

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

RETRY_QUEUE = "telemetry.measurements.retry"
DLX_EXCHANGE = "telemetry.dlx"
DLQ_QUEUE = "telemetry.measurements.dlq"

RETRY_ROUTING_KEY = "measurement.retry"
DLQ_ROUTING_KEY = "telemetry.dead"

RETRY_TTL_MS = 10000
MAX_RETRIES = 3


# PostgreSQL connection

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


# Prometheus metrics

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

rabbitmq_messages_retried = Counter(
    "rabbitmq_messages_retried_total",
    "Total messages published for retry"
)

rabbitmq_messages_dead_lettered = Counter(
    "rabbitmq_messages_dead_lettered_total",
    "Total messages sent to the dead-letter queue"
)


# RabbitMQ connection

def create_rabbitmq_connection():
    credentials = pika.PlainCredentials(
        RABBITMQ_USER,
        RABBITMQ_PASSWORD
    )

    parameters = pika.ConnectionParameters(
        host=RABBITMQ_HOST,
        port=RABBITMQ_PORT,
        credentials=credentials,
        connection_attempts=10,
        retry_delay=5,
        heartbeat=60
    )

    return pika.BlockingConnection(parameters)


rabbitmq_connection = create_rabbitmq_connection()
channel = rabbitmq_connection.channel()

# Enable publisher confirms for retry/DLQ publishing.
channel.confirm_delivery()


# Exchanges

channel.exchange_declare(
    exchange=RABBITMQ_EXCHANGE,
    exchange_type="direct",
    durable=True
)

channel.exchange_declare(
    exchange=DLX_EXCHANGE,
    exchange_type="direct",
    durable=True
)


# Main queue.
# IMPORTANT: Do not add x-dead-letter arguments here.
# This queue already exists without those arguments.

channel.queue_declare(
    queue=RABBITMQ_QUEUE,
    durable=True
)

channel.queue_bind(
    exchange=RABBITMQ_EXCHANGE,
    queue=RABBITMQ_QUEUE,
    routing_key=RABBITMQ_ROUTING_KEY
)


# Retry queue.
# Messages expire after 10 seconds and return to the main exchange.

channel.queue_declare(
    queue=RETRY_QUEUE,
    durable=True,
    arguments={
        "x-message-ttl": RETRY_TTL_MS,
        "x-dead-letter-exchange": RABBITMQ_EXCHANGE,
        "x-dead-letter-routing-key": RABBITMQ_ROUTING_KEY
    }
)

channel.queue_bind(
    exchange=RABBITMQ_EXCHANGE,
    queue=RETRY_QUEUE,
    routing_key=RETRY_ROUTING_KEY
)


# Dead-letter exchange and queue.

channel.queue_declare(
    queue=DLQ_QUEUE,
    durable=True
)

channel.queue_bind(
    exchange=DLX_EXCHANGE,
    queue=DLQ_QUEUE,
    routing_key=DLQ_ROUTING_KEY
)


# Process one message at a time.

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


def publish_with_confirm(
    exchange,
    routing_key,
    body,
    properties
):
    channel.basic_publish(
        exchange=exchange,
        routing_key=routing_key,
        body=body,
        properties=properties,
        mandatory=True
    )


def callback(ch, method, properties, body):
    headers = dict(
        properties.headers or {}
    )

    retry_count = int(
        headers.get("x-retry-count", 0)
    )

    try:
        measurement = json.loads(body)

        process_measurement(measurement)

        processed_measurements.inc()
        rabbitmq_messages_processed.inc()

        ch.basic_ack(
            delivery_tag=method.delivery_tag
        )

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

        # Preserve existing message headers and add retry count.
        headers["x-retry-count"] = retry_count + 1

        properties_out = pika.BasicProperties(
            delivery_mode=2,
            content_type=properties.content_type,
            headers=headers
        )

        try:
            if retry_count < MAX_RETRIES:
                # Publish to retry queue through the main exchange.
                # ACK original only after publisher confirmation.

                publish_with_confirm(
                    exchange=RABBITMQ_EXCHANGE,
                    routing_key=RETRY_ROUTING_KEY,
                    body=body,
                    properties=properties_out
                )

                ch.basic_ack(
                    delivery_tag=method.delivery_tag
                )

                rabbitmq_messages_retried.inc()

                print(
                    f"Message scheduled for retry "
                    f"{retry_count + 1}/{MAX_RETRIES}",
                    flush=True
                )

            else:
                # Retry limit reached: publish to DLQ.

                publish_with_confirm(
                    exchange=DLX_EXCHANGE,
                    routing_key=DLQ_ROUTING_KEY,
                    body=body,
                    properties=properties_out
                )

                ch.basic_ack(
                    delivery_tag=method.delivery_tag
                )

                rabbitmq_messages_dead_lettered.inc()

                print(
                    "Message sent to dead-letter queue",
                    flush=True
                )

        except Exception as publish_exc:
            # Do not ACK the original if forwarding was not confirmed.
            print(
                f"Retry/DLQ publish failed: {publish_exc}",
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
