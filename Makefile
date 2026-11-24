# Scaling PostgreSQL lab — common commands. Run `make` or `make help` for the list.
# Passwords come from .env (git-ignored). Create it with `make env`.

SHELL := /bin/bash
DC    := docker compose --env-file .env -f docker/single.yml
PSQL  := docker exec -i pg psql -U postgres -d app -v ON_ERROR_STOP=1

# benchmark defaults (override: make bench LABEL=step5/x CLIENTS=64)
LABEL   ?= scratch/run
CLIENTS ?= 32
THREADS ?= 8
DURATION ?= 120
SCRIPTS ?= feed_lateral.sql@9 write.sql@1
PORT    ?= 5432
HOST    ?= pg
# Step 4 split benchmark
READ_HOSTS  ?= replica1,replica2
WRITE_RATE  ?= 30
RYW_MODE    ?= lsn
RYW_N       ?= 1000
RYW_PAUSE   ?= 0

.DEFAULT_GOAL := help
.PHONY: help env check-env set-passwords up down stop ps logs psql seed indexes rebuild \
        pool-up pool-down userlist replicas-up replicas-down \
        bench bench-sampled bench-split ryw top-queries index-report check clean-txlogs

help: ## show this list
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------- secrets
env: ## create .env with random passwords (won't overwrite an existing one)
	@if [ -f .env ]; then echo ".env already exists, leaving it alone"; else \
	  sed -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$$(python3 -c 'import secrets;print(secrets.token_hex(16))')/" \
	      -e "s/^REPLICATOR_PASSWORD=.*/REPLICATOR_PASSWORD=$$(python3 -c 'import secrets;print(secrets.token_hex(16))')/" \
	      .env.example > .env && chmod 600 .env && echo "wrote .env (random passwords, mode 600)"; fi

check-env:
	@[ -f .env ] || { echo "error: .env missing. Run: make env" >&2; exit 1; }

set-passwords: check-env ## apply the passwords in .env to the running databases
	@scripts/set-passwords.sh

# ---------------------------------------------------------------- database
up: check-env ## start the primary (override the connection limit: make up PG_MAX_CONN=2500)
	@$(if $(PG_MAX_CONN),PG_MAX_CONN=$(PG_MAX_CONN)) $(DC) up -d pg

down: ## stop and remove all lab containers (data volumes are kept)
	@$(DC) --profile pool --profile replicas down

stop: ## stop all lab containers without removing them
	@docker stop pg pgbouncer replica1 replica2 2>/dev/null || true

ps: ## show lab containers
	@docker ps -a --filter name='^(pg|pgbouncer|replica1|replica2)$$' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

logs: ## follow primary logs
	@docker logs -f --tail 50 pg

psql: ## SQL shell on the primary
	@docker exec -it pg psql -U postgres -d app

seed: ## load schema + 1M users / 20M follows / 10M posts (~5 min)
	@$(PSQL) < sql/schema.sql
	@$(PSQL) < sql/seed.sql

indexes: ## create the final Step 2 indexes
	@$(PSQL) < sql/step2_indexes.sql

rebuild: check-env ## DELETE all lab data and rebuild from scratch (needs CONFIRM=yes)
	@[ "$(CONFIRM)" = yes ] || { echo "This deletes all lab data. Run: make rebuild CONFIRM=yes" >&2; exit 1; }
	@$(DC) --profile pool --profile replicas down -v
	@$(DC) up -d pg
	@until docker exec pg pg_isready -q -U postgres -d app; do sleep 1; done
	@$(MAKE) -s seed indexes userlist

# ---------------------------------------------------------------- Step 3: PgBouncer
userlist: ## regenerate PgBouncer's auth file from the database
	@docker/pgbouncer/make-userlist.sh

pool-up: check-env userlist ## start PgBouncer (port 6432)
	@$(DC) --profile pool up -d pgbouncer

pool-down: ## stop PgBouncer
	@docker stop pgbouncer >/dev/null 2>&1 || true

# ---------------------------------------------------------------- Step 4: replicas
replicas-up: check-env ## prepare the primary and start 2 read replicas (ports 5433, 5434)
	@docker/replica/setup-primary.sh
	@$(DC) --profile replicas up -d replica1 replica2

replicas-down: ## stop the replicas
	@docker stop replica1 replica2 >/dev/null 2>&1 || true

# ---------------------------------------------------------------- benchmarks
bench: check-env ## pgbench run -> raw/$(LABEL)/  (vars: LABEL CLIENTS THREADS DURATION SCRIPTS PORT HOST)
	@$(DC) run --rm bench '/bench/run.sh $(LABEL) $(CLIENTS) $(THREADS) $(DURATION) "$(SCRIPTS)" $(PORT) $(HOST)'

bench-sampled: check-env ## like bench, plus CPU/memory/connection sampling every 5 s
	@bench/run_sampled.sh $(LABEL) $(CLIENTS) $(THREADS) $(DURATION) "$(SCRIPTS)" $(PORT) $(HOST)

bench-split: check-env ## Step 4: reads on READ_HOSTS + writes at WRITE_RATE/s on the primary
	@bench/run_split_sampled.sh $(LABEL) $(CLIENTS) "$(READ_HOSTS)" $(WRITE_RATE) $(DURATION)

ryw: check-env ## Step 4: read-your-writes test (vars: RYW_MODE=replica|lsn RYW_N RYW_PAUSE)
	@$(DC) run --rm bench 'python3 /bench/ryw_test.py $(RYW_MODE) $(RYW_N) $(RYW_PAUSE)'

top-queries: ## Step 1: queries using the most time (pg_stat_statements)
	@$(PSQL) < sql/step1_top_queries.sql

index-report: ## Step 2: index sizes and usage
	@$(PSQL) < sql/step2_index_report.sql

# ---------------------------------------------------------------- housekeeping
check: ## syntax-check scripts and compose file
	@for f in bench/*.sh docker/*/*.sh scripts/*.sh; do bash -n $$f || exit 1; done
	@python3 -m py_compile bench/*.py && rm -rf bench/__pycache__
	@$(DC) --profile pool --profile replicas --profile tools config -q
	@echo "all checks passed"

clean-txlogs: ## delete per-transaction pgbench logs (large, git-ignored)
	@find raw -type d -name txlog -prune -exec rm -rf {} + && echo "txlogs removed"
