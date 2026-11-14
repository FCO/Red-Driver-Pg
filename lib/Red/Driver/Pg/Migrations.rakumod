use Red::Driver::Pg::Support;

unit role Red::Driver::Pg::Migrations does Red::Driver::Pg::Support;

method migration-transactional-ddl(--> Bool:D) { True }
method migration-session {
    return (self, Any) unless self.dbh.^name eq 'DB::Pg';
    my $session = self.dbh.db;
    (self.new-connection($session), $session)
}
method migration-auto-column($column, Str $table --> List:D) {
    ($column.type.lc.contains('big') ?? 'BIGSERIAL' !! 'SERIAL', ' PRIMARY KEY')
}
method migration-lock(Bool :$read-only = False) {
    my $statement = self.execute('SELECT pg_try_advisory_lock(1380271181) AS acquired');
    LEAVE $statement.finish-transaction;
    self.migration-error('Another migration executor holds the database lock')
        unless $statement.row<acquired>.Str.lc eq any(<1 true t>);
}
method migration-unlock {
    my $statement = self.execute('SELECT pg_advisory_unlock(1380271181)');
    $statement.finish-transaction;
}
method migration-normalize-table($table) {
    my %automatic;
    my $statement = self.execute(q:to/SQL/, $table.name);
        SELECT column_name, column_default, is_identity
        FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = $1
        SQL
    LEAVE $statement.finish-transaction;
    loop {
        my $row := $statement.row;
        last if $row =:= IterationEnd || !$row;
        %automatic{$row<column_name>} = $row<is_identity> eq 'YES'
            || ($row<column_default> // '').starts-with('nextval(');
    }
    $table.clone(:columns($table.columns.map({
        .clone(:auto-increment(so %automatic{.name}))
    }).Array))
}

method migration-sql-options(--> Hash:D) {
    %(hash-comment => False, dash-comment-whitespace => False,
        reject-hint-comment => False, dollar-quotes => True)
}
method migration-string-literal(Str $value --> Str:D) {
    my $hex = $value.encode('utf8').map(*.fmt('%02x')).join;
    "convert_from(decode('$hex', 'hex'), 'UTF8')"
}
method migration-provision(IO::Path $folder, Str $name, %server --> Hash:D) {
    self.migration-error('Configure a test server for Pg') unless %server;
    my %parameters = %server;
    %parameters<dbname> //= 'postgres';
    my $admin = self.new(|%parameters);
    $admin.execute('CREATE DATABASE ' ~ $admin.table-name-wrapper($name));
    %parameters<dbname> = $name;
    %(parameters => %parameters, :$admin, created => True)
}
method migration-drop-temporary($admin, Str $name) {
    $admin.execute('DROP DATABASE ' ~ $admin.table-name-wrapper($name) ~ ' WITH (FORCE)');
}

method migration-alter-column(Str $table, $before, $column, Str $definition --> Array:D) {
    my $prefix = 'ALTER TABLE ' ~ self.table-name-wrapper($table)
        ~ ' ALTER COLUMN ' ~ self.table-name-wrapper($column.name);
    my @sql;
    @sql.push("$prefix TYPE {$column.type}") if $before.type ne $column.type;
    @sql.push($prefix ~ ($column.nullable ?? ' DROP NOT NULL' !! ' SET NOT NULL'))
        if $before.nullable != $column.nullable;
    @sql.Array
}
