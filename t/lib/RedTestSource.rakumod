# Select the same Red checkout for direct prove6 runs and the SQL executor.
sub red-test-source() is export {
    my $root = $?FILE.IO.parent.parent.parent;
    my $explicit = %*ENV<RED_SOURCE> // '';
    my $source = $explicit.chars ?? $explicit.IO
        !! '/red/lib'.IO.d ?? '/red'.IO
        !! $root.parent.add('Red');
    die "RED_SOURCE has no lib directory: $source" if $explicit.chars && !$source.add('lib').d;
    $source.add('lib').d ?? $source.add('lib').Str !! Empty
}
