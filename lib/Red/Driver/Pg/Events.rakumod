use v6;
use JSON::Fast;
use Red::Driver::Pg::Support;

=head2 Red::Driver::Pg::Events

#| PostgreSQL implementation of Red's global (multi-node) model events.
#| LISTEN needs the C<epoll> module available to DB::Pg; without it the driver
#| reports no support and Red falls back to its local event stream.
unit role Red::Driver::Pg::Events does Red::Driver::Pg::Support;

my constant GLOBAL-EVENTS-CHANNEL = 'red_events';

#| Stable, PostgreSQL-safe name derived from a table name.
sub identifier-hash(Str:D $value --> Str:D) {
    my Int $hash = 0x811c9dc5;
    for $value.encode('utf8').list -> $byte {
        $hash = (($hash +^ $byte) * 0x01000193) +& 0xffffffff
    }
    $hash.fmt('%08x')
}

method global-event-identifier(Str:D $kind, Str:D $table --> Str:D) {
    my $suffix = $table.subst(/ <-[\w]> /, '_', :g).subst(/ _+ /, '_', :g).lc;
    $suffix = $suffix.substr(0, 38) if $suffix.chars > 38;
    'red_' ~ $kind ~ '_' ~ $suffix ~ '_' ~ identifier-hash($table)
}

#| DB::Pg can consume notifications only when its epoll dependency is loadable.
method supports-global-events(--> Bool:D) {
    return False unless self.dbh.defined;
    my $epoll = try {
        require ::('epoll');
        ::('epoll')
    };
    return False if $!;
    $epoll.^name eq 'epoll'
}

#| AFTER INSERT trigger publishing the primary key through pg_notify.
method global-event-triggers(Mu:U $model --> Array:D) {
    my $table = self.table-name-wrapper($model.^table);
    my @columns = $model.^global-notification-columns;
    my $ids = @columns.map({
        self.migration-string-literal($_) ~ ', NEW.' ~ self.table-name-wrapper($_)
    }).join(', ');
    my $function = self.table-name-wrapper:
        self.global-event-identifier('event_fn', $model.^table);
    my $trigger = self.global-event-identifier('event_trg', $model.^table);
    my $model-name = self.migration-string-literal($model.^name);

    my $function-sql = q:to/SQL/;
    CREATE OR REPLACE FUNCTION {FUNCTION}() RETURNS trigger AS $red_event$
    BEGIN
        PERFORM pg_notify('red_events', json_build_object(
            'v', 1,
            'model', {MODEL},
            'ids', json_build_object({IDS})
        )::text);
        RETURN NEW;
    END;
    $red_event$ LANGUAGE plpgsql
    SQL
    $function-sql = $function-sql.subst('{FUNCTION}', $function, :g)
                                 .subst('{MODEL}', $model-name, :g)
                                 .subst('{IDS}', $ids, :g);

    my $drop-sql = 'DROP TRIGGER IF EXISTS ' ~ $trigger ~ ' ON ' ~ $table;
    my $create-sql = 'CREATE TRIGGER ' ~ $trigger
        ~ ' AFTER INSERT ON ' ~ $table
        ~ ' FOR EACH ROW EXECUTE FUNCTION ' ~ $function ~ '()';

    [
        (self.global-event-identifier('event_fn', $model.^table) => $function-sql),
        (self.global-event-identifier('event_drop', $model.^table) => $drop-sql),
        ($trigger => $create-sql),
    ]
}

#| Remove a notification trigger when a migration model stops being global-notifiable.
method migration-drop-global-event-trigger(Str:D $table, Str:D $name --> Str:D) {
    return '' unless $name.starts-with('red_event_trg_');
    'DROP TRIGGER IF EXISTS ' ~ self.table-name-wrapper($name)
        ~ ' ON ' ~ self.table-name-wrapper($table)
}

#| Notifications run outside the transaction that created the trigger, so use a
#| stable driver backed by the original DB::Pg handle to materialize rows.
method global-event-listener-driver {
    my $dbh = self.dbh;
    return self if $dbh.^can('listen');
    return ::('Red::Driver::Pg').new(:dbh($dbh.dbpg))
        if $dbh.^can('dbpg') && $dbh.dbpg.defined;
    self
}

#| Tap the shared channel and decode each payload into a Red notification.
method listen-global-events(@models, &on-event) {
    my $dbh = self.dbh;
    $dbh = $dbh.dbpg if $dbh.^can('dbpg') && !$dbh.^can('listen');
    my $supplier = $dbh.listen(GLOBAL-EVENTS-CHANNEL);
    $supplier.Supply.tap(-> $message {
        my %payload = try from-json($message) // {};
        &on-event(%payload) if %payload<model>:exists;
    })
}
