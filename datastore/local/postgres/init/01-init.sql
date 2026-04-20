-- =============================================================================
-- USERS DATABASE (platform-user-service)
-- =============================================================================

-- Create database (run while connected to postgres or another default db)
CREATE DATABASE users;

-- Create service user with password
CREATE USER users_service_user WITH PASSWORD 'users_service_user';

-- Grant database-level privileges
GRANT ALL PRIVILEGES ON DATABASE users TO users_service_user;

-- Connect to users database to configure schema
\c users;

-- PostgreSQL 15+ fix: remove default PUBLIC access so only the service user controls the schema
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Change owner of public schema to the service user (required for PostgreSQL 15+)
ALTER SCHEMA public OWNER TO users_service_user;

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO users_service_user;
GRANT USAGE, CREATE ON SCHEMA public TO users_service_user;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO users_service_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO users_service_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO users_service_user;

-- =============================================================================
-- FILES DATABASE (platform-file-management-service)
-- =============================================================================

CREATE DATABASE files;
CREATE USER files_service_user WITH PASSWORD 'files_service_user';
GRANT ALL PRIVILEGES ON DATABASE files TO files_service_user;

-- Connect to files database to configure schema
\c files;

-- PostgreSQL 15+ fix
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Change owner of public schema to the service user
ALTER SCHEMA public OWNER TO files_service_user;

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO files_service_user;
GRANT USAGE, CREATE ON SCHEMA public TO files_service_user;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO files_service_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO files_service_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO files_service_user;

-- =============================================================================
-- HUMANRESOURCES DATABASE (platform-hr-service)
-- =============================================================================

CREATE DATABASE humanresources;
CREATE USER hr_service_user WITH PASSWORD 'hr_service_user';
GRANT ALL PRIVILEGES ON DATABASE humanresources TO hr_service_user;

-- Connect to humanresources database to configure schema
\c humanresources;

-- PostgreSQL 15+ fix
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Change owner of public schema to the service user
ALTER SCHEMA public OWNER TO hr_service_user;

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO hr_service_user;
GRANT USAGE, CREATE ON SCHEMA public TO hr_service_user;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO hr_service_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO hr_service_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO hr_service_user;
