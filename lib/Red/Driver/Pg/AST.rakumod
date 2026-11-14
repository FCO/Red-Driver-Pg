use Red::AST;
use Red::AST::Value;
use Red::AST::Constraints;
use Red::AST::DriverExtension;
use X::Red::Exceptions;

unit module Red::Driver::Pg::AST;

#| A native range constructor with SQL expression arguments.
class Red::Driver::Pg::AST::Range does Red::AST::DriverExtension {
    has Str $.range-type = 'numrange';
    has Red::AST @.values;
    method returns { Str }
    method args { |@!values }
    method find-column-name { @!values.map(*.find-column-name).flat }
}

#| A PostgreSQL exclusion constraint with ordered expression/operator pairs.
class Red::Driver::Pg::AST::Exclude is Red::AST::Constraint {
    has Str $.name is required;
    has Str $.driver = '';
    has Str $.using = 'gist';
    has Red::AST @.keys;
    has Str @.operators;
    has Str @.opclasses;
    has Red::AST $.predicate;
    method args { |@!keys, |($!predicate if $!predicate.DEFINITE) }
}

sub sql-range($lower, $upper, Str :$bounds = '[)', Str :$type = 'numrange' --> Red::AST)
    is export {
    X::Red::Index.new(:reason('Invalid native range type identifier')).throw
        unless $type ~~ /^ <[A..Za..z_]> <[A..Za..z_0..9]>* $/;
    Red::Driver::Pg::AST::Range.new(:range-type($type), :values[
        ast-value($lower), ast-value($upper), ast-value($bounds)
    ])
}

