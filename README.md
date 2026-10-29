# Red::Driver::Pg

PostgreSQL driver for the [Red](https://github.com/FCO/Red) ORM.

This driver is distributed separately from Red. Installing Red alone does not install
`DB::Pg` or require PostgreSQL client libraries.

## Install

Install the PostgreSQL client library (`libpq`) and then both distributions:

    zef install Red Red::Driver::Pg

## Synopsis

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

schema(Person).drop.create;
Person.^create: :name<Fernando>;
.say for Person.^all;
```

The constructor accepts `dbh`, `user`, `password`, `host`, `port`, and `dbname`.
`dbh` can be an existing `DB::Pg` object. The default host is `127.0.0.1` and the
default port is `5432`.

## Tests

The test executor creates a separate disposable database for every test file and drops
it afterward. The configured PostgreSQL user needs permission to create and drop databases.

Install the test tooling and the dependencies of both checkouts:

    zef install --/test --test-depends --deps-only .
    zef install --/test --test-depends --deps-only /path/to/Red
    zef install --/test App::Prove6 Config Config::Parser::json Configuration

Set `RED_SOURCE` to a Red checkout and configure the connection with `PGHOST`, `PGPORT`,
`PGUSER`, `PGPASSWORD`, and optionally `PGDATABASE` for the maintenance database. Then run:

    RED_SOURCE=/path/to/Red sh tools/test.sh

This runs the driver-specific tests followed by the complete Red suite against PostgreSQL.
`TEST_JOBS` controls parallelism and defaults to 4. Set `RAKUDO_RAKUAST=1` to test the
RakuAST frontend.

To run only the driver-specific tests:

    prove6 -j 4 -e "bash $PWD/tools/pg-test-exec.sh" t

GitHub Actions runs both suites with PostgreSQL 15, Rakudo 2026.09, the Red `master`
branch, and both RakuAST frontend settings.

## Author

Fernando Correa de Oliveira <fernandocorrea@gmail.com>

## Copyright and license

Copyright 2018 Fernando Correa de Oliveira

This library is free software; you can redistribute it and/or modify it under the
Artistic License 2.0.
