#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
    echo "Usage: $0 TEST_FILE" >&2
    exit 2
fi

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
red_source=${RED_SOURCE:-/red}
if [ -z "${RED_SOURCE:-}" ] && [ ! -d "$red_source/lib" ] && [ -d "$source_root/../Red/lib" ]; then
    red_source="$source_root/../Red"
fi
export PGHOST=${PGHOST:-127.0.0.1}
export PGPORT=${PGPORT:-5432}
export PGUSER=${PGUSER:-postgres}
maintenance_db=${PGDATABASE:-postgres}
database="red_pg_test_$$"
database_created=false
role_created=false

cleanup() {
    local status=$?
    if "$database_created"; then
        if dropdb --maintenance-db="$maintenance_db" --if-exists "$database"; then
            :
        else
            local cleanup_status=$?
            echo "Failed to remove PostgreSQL test database $database" >&2
            if (( status == 0 )); then
                status=$cleanup_status
            fi
        fi
    fi
    if "$role_created"; then
        if PGDATABASE="$maintenance_db" dropuser --if-exists "$database"; then
            :
        else
            local cleanup_status=$?
            echo "Failed to remove PostgreSQL test role $database" >&2
            if (( status == 0 )); then
                status=$cleanup_status
            fi
        fi
    fi
    exit "$status"
}
trap cleanup EXIT

# Native row security rejects superuser/BYPASSRLS connections. Give each test
# its own ordinary login and database; keep administrative credentials for cleanup.
PG_RUNNER_PASSWORD=${PGPASSWORD:-} psql -X -q --dbname="$maintenance_db" \
    --set=ON_ERROR_STOP=1 --set=role="$database" <<'SQL'
\getenv password PG_RUNNER_PASSWORD
SELECT format('CREATE ROLE %I LOGIN CREATEDB NOSUPERUSER NOBYPASSRLS PASSWORD %L', :'role', :'password') \gexec
SQL
role_created=true
createdb --maintenance-db="$maintenance_db" --template=template0 --owner="$database" "$database"
database_created=true
export RED_DATABASE="Pg host=$PGHOST port=$PGPORT dbname=$database user=$database"
raku "-I$source_root/lib" "-I$red_source/lib" "$1"
