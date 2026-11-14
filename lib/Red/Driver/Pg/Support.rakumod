use Red::AST;
use Red::AST::Infix;
use Red::AST::Unary;
use Red::AST::Value;
use Red::Index;
use Red::Driver::CommonSQL;
unit role Red::Driver::Pg::Support does Red::Driver::CommonSQL;

method database-client(--> Hash) {
    my %parameters = self.^attributes.map({ .name.substr(2) => .get_value(self) }).Hash;
    my %environment;
    for <host port user dbname password> Z <PGHOST PGPORT PGUSER PGDATABASE PGPASSWORD>
            -> ($parameter, $variable) {
        %environment{$variable} = %parameters{$parameter}.Str if %parameters{$parameter}.defined;
    }
    %(command => ['psql'], environment => %environment.Hash)
}

method advance-sequences(@models) {
    for @models -> $model {
        for $model.^columns.grep(*.column.auto-increment) -> $attribute {
            my $column = $attribute.column;
            my $sequence = self.execute('SELECT pg_get_serial_sequence($1, $2) AS sequence',
                self.table-name-wrapper($model.^table), $column.name).row<sequence>;
            next unless $sequence.defined;
            my $maximum = self.execute('SELECT MAX(' ~ self.table-name-wrapper($column.name)
                ~ ') AS maximum FROM ' ~ self.table-name-wrapper($model.^table)).row<maximum>;
            next unless $maximum.defined;
            my %identifier = self.execute('SELECT n.nspname AS schema_name, c.relname AS sequence_name '
                ~ 'FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace '
                ~ 'WHERE c.oid = CAST($1 AS regclass)', $sequence).row;
            my $qualified = <schema_name sequence_name>.map({
                self.table-name-wrapper(%identifier{$_})
            }).join('.');
            my $current = self.execute('SELECT last_value FROM ' ~ $qualified).row<last_value>;
            self.execute('SELECT setval(CAST($1 AS regclass), $2, true)', $sequence, $maximum)
                if $maximum >= $current;
        }
    }
}

method normalize-index-expression($ast) {
    my %changes;
    for $ast.^attributes -> $attribute {
        my $key = $attribute.name.substr(2);
        my $value = $attribute.get_value($ast);
        if $value ~~ Red::AST:D {
            %changes{$key} = self.normalize-index-expression($value);
        } elsif $value ~~ Positional {
            %changes{$key} = $value.map({
                $_ ~~ Red::AST:D ?? self.normalize-index-expression($_) !! $_
            }).Array;
        }
    }
    # PostgreSQL records the implicit conversion of integer constants adjacent
    # to numeric casts. Emit it explicitly so DDL and catalog identities agree.
    if $ast ~~ Red::AST::Infix {
        for <left right>, <right left> -> ($side, $other) {
            my $cast = %changes{$side};
            my $literal = %changes{$other};
            if $cast ~~ Red::AST::Cast && $cast.type.lc eq any(<num numeric>)
                && $literal ~~ Red::AST::Value && $literal.type =:= Int {
                %changes{$other} = Red::AST::Cast.new($literal, $cast.type);
            }
        }
    }
    $ast.clone: |%changes
}

method index-key-fingerprint(Str $key --> Str) {
    canonical-index-key($key, :normalize-tokens(-> @tokens {
    # PostgreSQL inserts text casts in text functions. Do not erase a standalone
    # cast: an index on id::text is different from an index on integer id.
    my @text-context;
    my Int $i = 0;
    while $i < @tokens.elems - 1 {
        if @tokens[$i] eq '(' {
            @text-context.push: $i > 0 && @tokens[$i - 1] eq any(
                <lower upper length char_length substring substr trim btrim ltrim rtrim replace strpos>
            );
        } elsif @tokens[$i] eq ')' {
            @text-context.pop;
        }
        if @tokens[$i] eq '::' && @tokens[$i + 1] eq 'text' && @text-context.grep(*.Bool) {
            @tokens.splice($i, 2);
        } else {
            $i++;
        }
    }
        @tokens
    }))
}
