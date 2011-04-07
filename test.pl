#!/usr/local/bin/perl -d

use strict;
use warnings;

use lib 'lib';
use lib '/opt/apache/sites/Projects/ElasticSearch/lib';
use ElasticSearchX::Autocomplete;

our ( $c, $e );

BEGIN {
    $c = ElasticSearch->new(
        servers   => '127.0.0.1:9200',
        transport => 'httplite'
    );
    $e = ElasticSearchX::Autocomplete->new(
        es         => $c,
        index      => 'suggest',
        type       => 'phrase',
        min_length => 1,
        stop_words => [],
        debug      => 1,
    );

}

sub restart {
    eval { $e->delete_index() };
    $e->create_index;
    $e->create_type();
}

sub parse {
    $e->index_phrases(
        min_freq => 2,

        #        filename => 'phrases.json',
        query => {
            index => 'iannounce_object',
            type  => [
                'memorial', 'anniversary', 'wedding', 'birthday',
                'bestwish', 'specialday'
            ],
            query => {
                constant_score => {
                    filter => {
                        and => [
                            { term   => { parent_id => 2876932 } },
                            { exists => { field     => 'location' } }
                        ]
                    }
                }
                }

        },
        parser => sub {
            my ( $e, $doc ) = @_;
            my $src = $doc->{_source};
            my ( $pid, $region, $source )
                = map { $src->{$_} } qw(parent_id region source );
            my @contexts = ( $pid, "$pid $region", "$pid $region $source" );
            my @locations;

            my $location = $src->{location};
            $location =~ s/[()0-9]+//g;
            $location =~ s/\b(a|aux|le|la|les|du|de|d),/$1 /gi;
            $location =~ s/' /'/g;
            $location =~ s/\s*-\s*/-/g;

            for ( grep {$_} split /\s*,\s*/, $location ) {
                next unless $_;
                push @locations, lc $_;
            }
            return
                map { { phrase => $_, label => $_, contexts => \@contexts } }
                @locations;
        }
    );
}
