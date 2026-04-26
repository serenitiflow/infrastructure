-- ============================================================
-- PART 1: Run this connected to the 'postgres' database
--         as the Aurora master user
-- ============================================================

-- Create the database
CREATE DATABASE humanresources;

-- Create the user with password
CREATE USER hr_service_user WITH PASSWORD 'hr_service_user';

-- Grant connection and database-level privileges
GRANT ALL PRIVILEGES ON DATABASE humanresources TO test;

-- ============================================================
-- PART 2: Run this connected to the 'humanresources' database
--         as the Aurora master user
-- ============================================================

-- Grant access to the public schema
GRANT ALL PRIVILEGES ON SCHEMA public TO hr_service_user;

-- Grant access to all existing tables
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO hr_service_user;

-- Grant access to all existing sequences
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO hr_service_user;

-- Grant access to all existing functions
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO hr_service_user;

-- Grant access to all existing procedures
GRANT ALL PRIVILEGES ON ALL PROCEDURES IN SCHEMA public TO hr_service_user;

-- Auto-grant on future objects created by the master user
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON TABLES TO hr_service_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON SEQUENCES TO hr_service_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON FUNCTIONS TO hr_service_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON ROUTINES TO hr_service_user;

-- Optional: grant rds_superuser role if 'test' needs
-- elevated privileges (manage users, replication, logs, etc.)
GRANT rds_superuser TO hr_service_user;