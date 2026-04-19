# SerenityFlow Infrastructure

Local development infrastructure for SerenityFlow platform.

## Services

| Service | Port | Purpose |
|---------|------|---------|
| PostgreSQL | 5432 | Multi-tenant data (`users` database) |
| Redis | 6379 | Sessions, caching, rate limiting |

## Quick Start

```bash
# Start infrastructure
docker-compose up -d

# Verify
docker ps
```

## Credentials

### PostgreSQL
- **Root:** postgres / postgres
- **App:** users_service_user / users_service_user
- **Database:** users

### Redis
- **User:** default
- **Password:** GxyvffifbjINAUNNUQp

## Management

```bash
# View logs
docker-compose logs -f

# Stop
docker-compose down

# Reset (removes all data)
docker-compose down -v
```
