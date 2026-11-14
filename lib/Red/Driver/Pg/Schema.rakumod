need Red::Driver::Pg::AST;
use Red::Attr::Index;
use Red::Index;
use Red::AST::Value;

unit module Red::Driver::Pg::Schema;

sub build-exclusion($attr, Mu:U $model) {
    my $name = index-name($model.^table, $attr.name.substr(2), False, :suffix<excl>);
    my $result = evaluate-index($attr.index-expression, $model);
    my @pairs = $result ~~ Positional ?? $result.list !! ($result,);
    index-error('EXCLUDE requires expression/operator pairs')
        unless @pairs && @pairs.all ~~ Pair;
    my @operators = @pairs.map(*.value);
    index-error('Unsupported exclusion operator')
        unless @operators.map({ $_ ~~ Str && $_ eq any(
            '=', '<>', '&&', '@>', '<@', '-|-', '<<', '>>', '&<', '&>'
        ) }).all;
    my %options = schema-options($attr, $model, @pairs.elems);
    my @opclasses = |(%options<opclasses>:delete);
    my @keys = @pairs.map({ index-expression(.key, $model) });
    Red::Driver::Pg::AST::Exclude.new(:$name, |%options,
        :@keys, :@operators, :@opclasses);
}

sub validate-schema-options(%options) {
    index-error('Unknown schema option') if %options.keys.grep({ $_ ne any(<using driver opclass where>) });
}

multi trait_mod:<is>(Attribute $attr, :&exclude! --> Empty) is export {
    $attr does Red::Attr::Index;
    $attr.configure-index(&exclude, :kind<exclude>, :using<gist>, :constraint-builder(&build-exclusion));
}

multi trait_mod:<is>(Attribute $attr, :$exclude! (&expression, *%options) --> Empty) is export {
    validate-schema-options(%options);
    $attr does Red::Attr::Index;
    $attr.configure-index(&expression, :kind<exclude>, :using<gist>, :constraint-builder(&build-exclusion), |%options);
}


sub sql-range(|args) is export {
    Red::Driver::Pg::AST::EXPORT::DEFAULT::<&sql-range>(|args)
}
