#!perl

use Test::More tests => 1;

BEGIN {
    use_ok( 'ElasticSearchX::Autocomplete' ) || print "Bail out!
";
}

diag( "Testing ElasticSearchX::Autocomplete $ElasticSearchX::Autocomplete::VERSION, Perl $], $^X" );
