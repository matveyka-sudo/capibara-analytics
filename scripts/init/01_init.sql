-- Runs only when PostgreSQL initializes a fresh database volume.

CREATE SCHEMA IF NOT EXISTS raw;

CREATE SCHEMA IF NOT EXISTS core;

CREATE SCHEMA IF NOT EXISTS mart;

ALTER DATABASE marketplace SET search_path TO core, public;
