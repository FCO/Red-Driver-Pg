Red::Driver::Pg
===============

PostgreSQL driver for the [Red](https://github.com/FCO/Red) ORM.

This driver requires Red 0.2.16 or later with API 2 and is distributed separately from Red. Installing Red alone does not install `DB::Pg` or require PostgreSQL client libraries.

Install
-------

Install the PostgreSQL client library (`libpq`) and then both distributions:

    zef install Red Red::Driver::Pg

Synopsis
--------

```raku
use Red:api<2>;

model Person {
    has Int $.id is serial;
    has Str $.name is column;
}

my $*RED-DB = database "Pg",
    host => "127.0.0.1",
    port => 5432,
    dbname => "my_database",
    user => "my_user",
    password => "my_password";

schema(Person).create;
Person.^create: :name<Fernando>;
.say for Person.^all;
```

The constructor accepts `dbh`, `user`, `password`, `host`, `port`, and `dbname`. `dbh` can be an existing `DB::Pg` object. The default host is `127.0.0.1` and the default port is `5432`.

Global events
-------------

Models marked with `is global-notifiable` publish committed inserts through PostgreSQL `AFTER INSERT` triggers and `pg_notify` on the `red_events` channel. Notifications are delivered at commit, so `ResultSeq.Supply` works across processes and nodes without local duplicate events. Trigger DDL is captured in migration snapshots.

`DB::Pg` LISTEN support depends on the `epoll` module. When it is unavailable this driver reports no global-event support and Red falls back to local events with a warning.

Tests
-----

The test executor creates a separate disposable login and database for every test file and drops both afterward. The configured PostgreSQL user needs permission to create and drop roles and databases. Test logins are neither superusers nor `BYPASSRLS` roles.

Install the test tooling and the dependencies of both checkouts:

    zef install --/test --test-depends --deps-only .
    zef install --/test --test-depends --deps-only /path/to/Red
    zef install --/test App::Prove6 Config Config::Parser::json Configuration

Set `RED_SOURCE` to a Red checkout and configure the connection with `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, and optionally `PGDATABASE` for the maintenance database. Then run:

    RED_SOURCE=/path/to/Red sh tools/test.sh

This runs the driver-specific tests followed by the complete Red suite against PostgreSQL. `TEST_JOBS` controls parallelism and defaults to 4. Set `RAKUDO_RAKUAST=1` to test the RakuAST frontend.

When available, the test tools use `/red` or a sibling `../Red` checkout automatically.
Set `RED_SOURCE` to select a different checkout. Direct `prove6 -lv t` runs use the
same selection; without a checkout they use the installed Red distribution.

To run only the driver-specific tests:

    prove6 -j 4 -e "bash $PWD/tools/pg-test-exec.sh" t

`mi6 test` also runs the PostgreSQL integration files. Without a Pg `RED_DATABASE`, these files invoke the executor to create and remove their own logins and databases, using `PGHOST` (default `127.0.0.1`), `PGPORT` (`5432`), and `PGUSER` (`postgres`). PostgreSQL and the `psql`, `createdb`/`dropdb`, and `dropuser` client tools must be available; connection or resource creation failures fail the tests instead of skipping them.

GitHub Actions runs both suites with PostgreSQL 15, Rakudo 2026.09, the Red `master` branch, and both RakuAST frontend settings.

Documentation maintenance
-------------------------

Edit `lib/Red/Driver/Pg.rakudoc` to update this documentation. Mi6 generates `README.md` from this file through the `ReadmeFromPod` configuration in `dist.ini`. Comments in the driver module are not the README source.

Author
------

Fernando Correa de Oliveira <fernandocorrea@gmail.com>

Copyright and license
---------------------

Copyright 2018 Fernando Correa de Oliveira

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

