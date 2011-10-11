package ElasticSearchX::Autocomplete::Type;

use strict;
use warnings FATAL => 'all';
use Carp;

use Text::Unidecode;
use Unicode::Normalize;
use List::MoreUtils qw(uniq);
use ElasticSearchX::Autocomplete::Util
    qw(_create_accessors _params _debug _try_cache cache_key );

__PACKAGE__->_create_accessors(
    ['cache'],
    ['debug'],
    ['JSON'],
    ['tokenizer'],
    ['formatter'],
    ['ascii_folding'],
    ['geoloc'],
    ['multi_tokens'],
    [ 'max_results',        10 ],
    [ 'min_length',         1 ],
    [ 'max_tokens',         10 ],
    [ 'match_boost',        1 ],
    [ 'custom_fields',      '{}' ],
    [ 'popular_filters',    '[]' ],
    [ 'suggestion_filters', '[]' ],
    [ 'es',                 q(croak "Missing required param 'es'") ],
    [ 'index',              q(croak "Missing required param 'index'") ],
    [ 'name',               q(croak "Missing required param 'name'") ],
);

#===================================
sub new {
#===================================
    my ( $proto, $params ) = _params(@_);
    my $class = ref $proto || $proto;

    my $self = {
        _ascii_folding => 1,
        _tokenizer     => $class->can('_tokenize'),
        _formatter     => $class->can('_format'),
        _debug         => 0
    };

    bless $self, $class;
    $self->$_( $params->{$_} ) for keys %$params;

    return $self;
}

our $as_json;

#===================================
sub suggest {
#===================================
    my $self   = shift;
    my $params = $self->_search_params(@_);

    $self->_debug(
        1, 'Suggest: ',
        join( ':', @{$params}{qw(index type context)}, '' ),
        $params->{tokens} || '<NONE>'
    );

    return $self->_try_cache( '_suggestions', $params, $as_json );
}

#===================================
sub suggest_json {
#===================================
    local $as_json = 1;
    return shift()->suggest(@_);
}

#===================================
sub _search_params {
#===================================
    my $self = shift;
    my ( $phrase, $params ) = _params(@_);

    $phrase = '' unless defined $phrase;

    my %search_params = (
        context     => _clean_context( $params->{context} ),
        index       => $self->index,
        type        => $self->name,
        size        => $params->{max_results} || $self->max_results,
        match_boost => $params->{match_boost} || $self->match_boost,
    );

    my @tokens = $self->tokenize($phrase);
    if ( $phrase =~ /\w$/ ) {
        my $last = pop @tokens;
        @tokens = ( $self->filter_tokens(@tokens), $last );
    }
    else {
        @tokens = $self->filter_tokens(@tokens);
    }
    $search_params{tokens} = \@tokens
        if @tokens;

    for (qw(location loose)) {
        $search_params{$_} = $params->{$_}
            if $params->{$_};
    }
    return \%search_params;
}

#===================================
sub _suggestions {
#===================================
    my $self   = shift;
    my $params = shift;

    my $search
        = $params->{tokens}
        ? $self->_retrieve_suggestions($params)
        : $self->_retrieve_popular($params);

    my $results = $self->_context_search( $params, $search );
    return $self->format_suggestions( $params, $results );

}

#===================================
sub format_suggestions { $_[0]->{_formatter}->(@_) }
#===================================

#===================================
sub _format {
#===================================
    my $self    = shift;
    my $params  = shift;
    my $results = shift;

    my $cb = $self->label_builder( $self->ascii_folding, $params->{tokens} );

    return [ map { $cb->($_) } @$results ];
}

#===================================
sub label_builder {
#===================================
    my $self      = shift;
    my $use_ascii = shift;
    my $tokens    = shift || [];

    my $canonicalize;
    if ($use_ascii) {
        $tokens = [ map { unidecode($_) } @$tokens ];
        $canonicalize = sub {
            map { $_ => unidecode($_) } @_;
        };
    }
    else {
        $canonicalize = sub {
            map { $_ => $_ } @_;
        };
    }

    return sub {
        my $doc   = shift;
        my $label = $doc->{_source}{label};
        return $label if $label;

        my $result     = $doc->{_source}{tokens};
        my @candidates = ref $result ? @$result : $result;
        my %unused     = $canonicalize->(@candidates);
        my @new_tokens;

    ORIGINAL: for my $token (@$tokens) {
            for my $candidate ( keys %unused ) {
                if ( $unused{$candidate} =~ /^${token}/i ) {
                    delete $unused{$candidate};
                    push @new_tokens, $candidate;
                    next ORIGINAL;
                }
            }
        }

        for my $candidate ( sort @candidates ) {
            push @new_tokens, $candidate
                if $unused{$candidate};
        }
        return join ' ', @new_tokens;
    };
}

#===================================
sub _retrieve_suggestions {
#===================================
    my $self   = shift;
    my $params = shift;
    my @tokens = @{ $params->{tokens} };
    my $qs     = join ' ', @tokens;

    my $ngrams
        = $params->{loose}
        ? $qs
        : join ' ', map {"+$_"} @tokens;

    my $tokens_field = $self->multi_tokens ? 'tokens.tokens' : 'tokens';
    my $token_query = {
        -bool => {
            must   => { "$tokens_field.ngram" => { -qs => $ngrams } },
            should => {
                $tokens_field => {
                    '=' => { query => $qs, boost => $params->{match_boost} }
                }
            }
        }
    };

    if ( $self->multi_tokens ) {
        $token_query = {
            context => $params->{context},
            -nested => {
                path       => 'tokens',
                score_mode => 'max',
                query      => $token_query
            }
        };
    }

    $token_query->{-filter} = {
        context => $params->{context},
        @{ $self->suggestion_filters }
    };

    my $search = {
        explain => 0,
        fields  => ['_source'],
        queryb  => $token_query,
    };
    return $self->_location_clause( $params, $search );

}

#===================================
sub _location_clause {
#===================================
    my $self   = shift;
    my $params = shift;
    my $search = shift;

    my $loc = $params->{location} or return $search;
    my $lat = $loc->{lat};
    my $lon = $loc->{lon};

    return $search unless defined $lat && defined $lon;

    my $radius = $loc->{radius} || 1000;
    my $exp    = $loc->{exp}    || 2;
    my $steps  = $loc->{steps}  || 4;
    my $boost  = $loc->{boost}  || 5;
    my $step   = $boost / $steps;

    my @filters;
    for ( reverse 0 .. $steps - 1 ) {
        unshift @filters,
            {
            boost  => $boost - $step * $_,
            filter => {
                location => {
                    -geo_distance => {
                        location => { lat => $lat, lon => $lon },
                        distance => $radius . 'km'
                    }
                }
            },
            };
        $radius /= $exp;
    }

    $search->{queryb} = {
        -custom_filters_score => {
            query   => $search->{queryb},
            filters => \@filters
        }
    };
    $search->{script_fields} = {
        distance => {
            script => "floor(doc['location'].distanceInKm(lat,lon))",
            params => { lat => $lat, lon => $lon },
        }
    };

    return $search;

}

#===================================
sub _retrieve_popular {
#===================================
    my $self    = shift;
    my $params  = shift;
    my $context = $params->{context};

    my @filters = ( { context => $context }, @{ $self->popular_filters } );

    if ( my $loc = $params->{location} ) {
        my $radius = $loc->{radius} || 500;
        push @filters,
            {
            location => {
                -geo_distance => {
                    location => { lat => $loc->{lat}, lon => $loc->{lon} },
                    distance => $radius . 'km',
                }
            }
            };
    }

    return {
        fields => ['_source'],
        queryb => { -filter => { -and => \@filters } },
        sort   => [ { 'rank' => 'desc' }, { 'label' => 'asc' } ],
    };

}

#===================================
sub _context_search {
#===================================
    my $self   = shift;
    my $params = shift;
    my $search = shift;

    my $results;
    eval {
        $results = $self->es->search(
            preference => '_local',
            explain    => 0,
            %$search,
            ( map { $_ => $params->{$_} } qw(index type size) ),
        );

    } and return $results->{hits}{hits};

    croak !defined $@                         ? 'Unknown error'
        : $@ !~ /No mapping found for \[rank/ ? $@
        :   'Unknown context: ' . $params->{context};
}

#===================================
sub filter_tokens {
#===================================
    my $self       = shift;
    my $min_length = $self->min_length;
    my $stop_words = $self->stop_words;
    my $max_tokens = $self->max_tokens;
    my @tokens     = grep {
                defined $_
            and length $_ >= $min_length
            and !$stop_words->{$_}
    } @_;

    $#tokens = $max_tokens - 1
        if @tokens >= $max_tokens;

    return @tokens;
}

#===================================
sub tokenize { $_[0]->{_tokenizer}->( $_[1] ) }
#===================================

#===================================
sub _tokenize {
#===================================
    my $str = shift;
    return unless defined $str;

    utf8::upgrade($str);
    $str = lc NFC $str;

    return grep {length} uniq split /\W+/, $str;
}

#===================================
sub clean_context { _clean_context( $_[1] ) }
#===================================

#===================================
sub _clean_context {
#===================================
    my $context = shift;
    $context = '/' unless defined $context;
    $context =~ tr{ }{/};
    $context = '/' . $context
        unless substr( $context, 0, 1 ) eq '/';
    return $context;
}

#===================================
sub stop_words {
#===================================
    my $self = shift;
    if (@_) {
        my @tokens = ref $_[0] ? @{ $_[0] } : @_;
        $self->{_stop_words} = { map { lc($_) => 1 } @tokens };
    }
    return $self->{_stop_words} || {};
}

=head1 NAME

ElasticSearchX::Autocomplete::Type

=head1 DESCRIPTION

To follow

=head1 SEE ALSO

L<ElasticSearchX::Autocomplete>

=head1 SEE ALSO

L<ElasticSearchX::Autocomplete>

=head1 AUTHOR

Clinton Gormley, E<lt>clinton@traveljury.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Clinton Gormley

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.


=cut

1
