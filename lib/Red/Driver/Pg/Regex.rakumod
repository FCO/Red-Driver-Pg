use Red::Regex;
use Red::Regex::Automaton;
unit class Red::Driver::Pg::Regex is Red::Regex;

method render(Str:D :$dialect = 'Pg' --> Str:D) {
    self.render-info(:$dialect)<pattern>
}

method render-info(Str:D :$dialect = 'Pg', :@capture-ids = (),
    Bool :$whole = False --> Hash:D) {
    self.unsupported("Unknown regex dialect: $dialect") unless $dialect eq 'Pg';
    my %*RED-REGEX-REFERENCED;
    my %*RED-REGEX-CAPTURES;
    my Int $*RED-REGEX-NEXT-CAPTURE = $whole ?? 1 !! 0;
    %*RED-REGEX-REFERENCED{$_} = True for @capture-ids;
    self.walk(-> $part {
        self.unsupported('Whole match reads with Match boundary markers are not implemented')
            if $whole && $part[0] eq 'match-boundary';
        self.unsupported('The same-character assertion has no implemented PostgreSQL lowering')
            if $part[0] eq 'same';
        if $part[0] eq 'backreference' {
            %*RED-REGEX-REFERENCED{$_} = True for $part[1].list;
        }
    });
    my $pattern = self!render(self.tree, $dialect, True);
    $pattern = '(?:)' unless $pattern.chars;
    if $whole {
        my $prefix = '';
        for '(?i)', '(?c)' -> $flag {
            if $pattern.starts-with($flag) {
                $prefix = $flag;
                $pattern = $pattern.substr($flag.chars);
                last;
            }
        }
        $pattern = $prefix ~ '(' ~ $pattern ~ ')';
    }
    { :$pattern, :groups(%*RED-REGEX-CAPTURES.Map) }
}

method !render($tree, Str:D $dialect, Bool $root = False, Bool $ignore = False --> Str:D) {
    my @part = $tree.list;
    given @part[0] {
        when 'empty' | 'match-boundary' { '' }
        when 'never' { '(?!)' }
        when 'literal-slot' { self.unsupported('Regex literal interpolation needs bound values') }
        when 'literal' { self.escape(@part[1]) }
        when 'sequence' { @part.skip(1).map({ self!render($_, $dialect, False, $ignore) }).join }
        when 'alternative' {
            '(?:' ~ @part.skip(1).map({ self!render($_, $dialect, False, $ignore) }).join('|') ~ ')'
        }
        when 'group' | 'scope' { '(?:' ~ self!render(@part[1], $dialect, False, $ignore) ~ ')' }
        when 'capture' {
            my $needed = so %*RED-REGEX-REFERENCED{@part[1]};
            if $needed {
                my Bool $boundary = False;
                self.walk(-> $node { $boundary = True if $node[0] eq 'match-boundary' }, @part[2]);
                self.unsupported('Capture references crossing Match boundaries are not supported')
                    if $boundary;
            }
            %*RED-REGEX-CAPTURES{@part[1]} = ++$*RED-REGEX-NEXT-CAPTURE if $needed;
            ($needed ?? '(' !! '(?:') ~ self!render(@part[2], $dialect, False, $ignore) ~ ')'
        }
        when 'backreference' {
            my @groups = @part[1].list.map({ %*RED-REGEX-CAPTURES{$_} }).grep(*.defined);
            self.unsupported('Forward or unmatched capture references are not supported')
                unless @groups;
            self.unsupported('PostgreSQL can only reference the first nine native capture groups')
                if @groups.max > 9;
            self.unsupported('Exact references under :i are not implemented for PostgreSQL')
                if $ignore;
            ($ignore ?? '(?-i:' !! '(?:') ~ @groups.map({ '\\' ~ $_ }).join('|') ~ ')'
        }
        when 'mode' {
            my $enabled = @part[1];
            self.unsupported('Scoped case modifiers are not supported by PostgreSQL')
                if !$root;
            ($enabled ?? '(?i)' !! '(?c)')
                ~ self!render(@part[2], $dialect, False, $enabled)
        }
        when 'intersection' {
            Red::Regex::Automaton.new(:tree(@part.List), :$ignore).render(
                -> $test, Bool $case {
                    if $test[0] eq 'empty' {
                        ''
                    } else {
                        my $label = $case == $ignore ?? $test !! ['mode', $case, $test];
                        self!render($label, $dialect, False, $ignore)
                    }
                })
        }
        when 'both' {
            my $left = @part[2] == $ignore ?? @part[1] !! ['mode', @part[2], @part[1]];
            my $right = @part[4] == $ignore ?? @part[3] !! ['mode', @part[4], @part[3]];
            '(?=' ~ self!render($left, $dialect, False, $ignore) ~ ')'
                ~ self!render($right, $dialect, False, $ignore)
        }
        when 'atomic' {
            self.unsupported('Atomic/ratcheted regexes are not supported by Pg')
        }
        when 'any' { '.' }
        when 'class' {
            my %classes = digit => '[:digit:]', word => '[:alnum:]_', space => '[:space:]',
                alpha => '[:alpha:]_', alnum => '[:alnum:]_', lower => '[:lower:]',
                upper => '[:upper:]', xdigit => '0-9A-Fa-f', blank => '[:blank:]',
                cntrl => '[:cntrl:]', graph => '[:graph:]', print => '[:print:]',
                punct => '[:punct:]';
            self.unsupported("Unknown character class: {@part[1]}")
                unless %classes{@part[1]}:exists;
            '[' ~ (@part[2] ?? '^' !! '') ~ %classes{@part[1]} ~ ']'
        }
        when 'ranges' {
            my &escape = -> Int:D $point {
                $point <= 0xFFFF ?? '\u' ~ $point.fmt('%04X')
                    !! '\U' ~ $point.fmt('%08X')
            };
            # An empty Unicode category is a valid set that matches no character.
            return '(?!)' unless @part[1].elems || @part[2];
            return '.' unless @part[1].elems;
            '[' ~ (@part[2] ?? '^' !! '') ~ @part[1].map({
                escape(.[0]) ~ (.[0] == .[1] ?? '' !! '-' ~ escape(.[1]))
            }).join ~ ']'
        }
        when 'set' {
            my $left = self!render(@part[2], $dialect, False, $ignore);
            my $right = self!render(@part[3], $dialect, False, $ignore);
            @part[1] eq 'union' ?? '(?:' ~ $left ~ '|' ~ $right ~ ')'
                !! @part[1] eq 'intersect' ?? '(?=' ~ $left ~ ')' ~ $right
                !! '(?!' ~ $right ~ ')' ~ $left
        }
        when 'characters' {
            my $positive = '(?:' ~ @part[1].ords.map({ self.escape(.chr) }).join('|') ~ ')';
            @part[2] ?? '(?!' ~ $positive ~ ').' !! $positive
        }
        when 'same' {
            self.unsupported('The same-character assertion has no implemented PostgreSQL lowering')
        }
        when 'anchor' {
            my $end = '\Z';
            given @part[1] {
                when 'begin' { '\A' }
                when 'end' { $end }
                when 'line-begin' { '(?:\A|(?<=\n))' }
                when 'line-end' { '(?:' ~ $end ~ '|(?=\n))' }
                when 'word-left' { '\m' }
                when 'word-right' { '\M' }
                when 'word' { '\y' }
                when 'not-word' { '\Y' }
                when 'not-within-word' { '(?:(?<!\w)|(?!\w))' }
                when 'within-word' { '(?<=\w)(?=\w)' }
                default { self.unsupported("Unknown anchor: {@part[1]}") }
            }
        }
        when 'look' {
            my $has-reference = False;
            self.walk(-> $part { $has-reference = True if $part[0] eq 'backreference' }, @part[3]);
            self.unsupported('PostgreSQL lookarounds cannot contain backreferences')
                if $has-reference;
            '(' ~ (@part[1] eq 'after' ?? '?<' !! '?') ~ (@part[2] ?? '!' !! '=')
                ~ self!render(@part[3], $dialect, False, $ignore) ~ ')'
        }
        when 'repeat' {
            my ($body, $minimum, $maximum, $frugal) = @part[1..4];
            if ($minimum > 255 || $maximum > 255) {
                my Bool $referenced-capture = False;
                self.walk(-> $part {
                    $referenced-capture = True if $part[0] eq 'capture'
                        && %*RED-REGEX-REFERENCED{$part[1]};
                }, $body);
                self.unsupported('Large repetition cannot duplicate referenced capture groups')
                    if $referenced-capture;
                my $atom = '(?:' ~ self!render($body, $dialect, False, $ignore) ~ ')';
                return self.pg-repeat($atom, $minimum, $maximum, $frugal);
            }
            my $suffix = $minimum == 0 && $maximum == -1 ?? '*'
                !! $minimum == 1 && $maximum == -1 ?? '+'
                !! $minimum == 0 && $maximum == 1 ?? '?'
                !! '{' ~ $minimum ~ ',' ~ ($maximum == -1 ?? '' !! $maximum) ~ '}';
            '(?:' ~ self!render($body, $dialect, False, $ignore) ~ ')' ~ $suffix ~ ($frugal ?? '?' !! '')
        }
        default { self.unsupported("Unsupported operation {@part[0]} on $dialect") }
    }
}

# Lower large bounds without emitting any native bound greater than 255.
method pg-repeat(Str:D $atom, Int:D $minimum, Int:D $maximum,
    Bool:D $frugal --> Str:D) {
    my $preference = $frugal ?? '?' !! '';
    sub exact(Str:D $unit, Int:D $count, Int:D $depth = 0 --> Str:D) {
        self.unsupported('PostgreSQL repetition lowering exceeds 16 nesting levels')
            if $depth > 16;
        return '' if $count == 0;
        return $unit ~ '{' ~ $count ~ '}' ~ $preference if $count <= 255;
        my $block = '(?:' ~ $unit ~ '{255}' ~ $preference ~ ')';
        exact($block, $count div 255, $depth + 1)
            ~ exact($unit, $count % 255, $depth + 1)
    }
    my $pattern = exact($atom, $minimum);
    if $maximum == -1 {
        $pattern ~= $atom ~ '*' ~ $preference;
    } else {
        my $optional = $maximum - $minimum;
        my $block = '(?:' ~ $atom ~ '{0,255}' ~ $preference ~ ')';
        $pattern ~= exact($block, $optional div 255);
        $pattern ~= $atom ~ '{0,' ~ ($optional % 255) ~ '}' ~ $preference
            if $optional % 255;
    }
    self.unsupported('PostgreSQL repetition lowering exceeds 64KiB of pattern text')
        if $pattern.chars > 65536;
    '(?:' ~ $pattern ~ ')'
}

