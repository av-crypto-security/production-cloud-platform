CREATE TABLE measurements (
	id SERIAL PRIMARY KEY,
	bridge_id VARCHAR(32),
	timestamp TIMESTAMPTZ,
	temperature FLOAT,
	humidity FLOAT,
	vibration FLOAT,
	tilt FLOAT,
	processed BOOLEAN DEFAULT FALSE
);

CREATE TABLE alerts (
	id SERIAL PRIMARY KEY,
	bridge_id VARCHAR(32),
	timestamp TIMESTAMPTZ,
	alert_type VARCHAR(64),
	severity VARCHAR(32),
	message TEXT
);
