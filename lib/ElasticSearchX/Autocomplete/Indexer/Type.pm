package ElasticSearchX::Autocomplete::Indexer::Type;

use strict;
use warnings FATAL => 'all';
use Carp;
use ElasticSearchX::Autocomplete::Util qw(_create_accessors _params _debug );

__PACKAGE__->_create_accessors(
    ['debug'],
    ['JSON'],
    [ 'es',    q(croak "Missing required param 'es'") ],
    [ 'index', q(croak "Missing required param 'index'") ],
    [ 'type',  q(croak "Missing required param 'type'") ],
);

#===================================
sub new {
#===================================
    my ( $proto, $params ) = _params(@_);
    my $class = ref $proto || $proto;
    my $self = { _debug => 0 };

    bless $self, $class;
    $self->$_( $params->{$_} ) for keys %$params;

    return $self;
}

#===================================
sub index_phrases {
#===================================
    my ( $self, $params ) = _params(@_);

    my $phrases = $params->{phrases}
        || $self->aggregate_phrases($params);

    my @recs;
    my $i         = 0;
    my $index     = $self->index;
    my $type      = $self->type;
    my $type_name = $type->name;
    my $clean     = $type->can('_clean_context');

    $self->_debug( 3, " - Indexing " . ( scalar @$phrases ) . " phrases" );

    for my $entry (@$phrases) {
        my $rank = delete $entry->{rank};
        my %cleaned = map { $clean->($_) => $rank->{$_} } keys %$rank;
        for ( keys %$entry ) {
            delete $entry->{$_} unless defined $entry->{$_};
        }

        push @recs,
            {
            index => $index,
            type  => $type_name,
            id    => delete $entry->{doc_id},
            data  => {
                rank => \%cleaned,
                %$entry,
            }
            };
        $self->_bulk_index( \@recs, $i )
            if ++$i % 5000 == 0;
    }

    $self->_bulk_index( \@recs, $i );
    $self->es->refresh_index( index => $index )
        unless $params->{no_refresh};
}

#===================================
sub _bulk_index {
#===================================
    my $self = shift;
    my $recs = shift;
    return unless @$recs;

    my $i      = shift;
    my $result = $self->es->bulk_index($recs);

    if ( my $err = $result->{errors} ) {
        my $JSON = $self->JSON;
        my @errors = map { $JSON->encode($_) } splice @$err, 0, 5;
        push @errors, sprintf "...and %d more", scalar @$err
            if @$err;
        croak( "Errors occurred while indexing:", \@errors );
    }

    $self->_debug( 3, "   - $i" );
    @$recs = ();

}

#===================================
sub aggregate_phrases {
#===================================
    my ( $self, $params ) = _params(@_);

    my $parser = $params->{parser}
        || croak "No parser callback passed to aggregate_phrases()";

    my $source;
    if ( my $query = $params->{query} ) {
        $source = $self->_es_iterator($query);
    }
    croak "No query or source passed to aggregate_phrases()"
        unless $source;

    my %phrases;
    my $total = 0;

    while ( my $doc = $source->() ) {
        my @vals = $parser->( $self, $doc );
        $self->add_doc( \%phrases, $_ ) for @vals;
        $self->_debug( 1, ' - ', $total )
            if ++$total % 1000 == 0;
    }

    $self->check_min_rank( \%phrases, $params->{min_rank} );

    return [ values %phrases ];
}

#===================================
sub _es_iterator {
#===================================
    my $self  = shift;
    my $query = shift;

    my $es     = $self->es;
    my $scroll = $es->scrolled_search(
        search_type => 'scan',
        size        => 100,
        scroll      => '5m',
        %$query,
    );

    $self->_debug( 1, "Aggregating ", $scroll->total, " records" );
    return sub { $scroll->next(1) };
}

#===================================
sub add_doc {
#===================================
    my $self    = shift;
    my $phrases = shift;
    my $vals    = shift;

    my $type = $self->type;
    my @tokens
        = $vals->{tokens}
        ? @{ delete $vals->{tokens} }
        : $type->tokenize( delete $vals->{phrase} || $vals->{label} );

    @tokens = $type->filter_tokens(@tokens);
    return unless @tokens;

    my $id = $vals->{id} || join "\t", sort @tokens;
    my $doc = $phrases->{$id} ||= {
        tokens => \@tokens,
        rank   => {},
        map { $_ => $vals->{$_} }
            ( qw(label doc_id location), keys %{ $type->custom_fields } )
    };

    my @contexts = @{ $vals->{contexts} || [] };
    @contexts = '/' unless @contexts;

    if ( my $rank = $vals->{rank} ) {
        $doc->{rank}{$_} = $rank for @contexts;
    }
    else {
        $doc->{rank}{$_}++ for @contexts;
    }

}

#===================================
sub clean_context { shift->type->_clean_context(@_) }
sub tokenize      { shift->type->tokenize(@_) }
#===================================

#===================================
sub check_min_rank {
#===================================
    my $self    = shift;
    my $phrases = shift;
    my $min     = shift || 1;
    return unless $min > 1;

    for my $id ( keys %$phrases ) {
        my $ranks = $phrases->{$id}{rank};
        for my $context ( keys %$ranks ) {
            delete $ranks->{$context}
                if $ranks->{$context} < $min;
        }
        delete $phrases->{$id}
            unless %$ranks;
    }
}

#===================================
sub init {
#===================================
    my $self = shift;

    my $es = $self->es;
    $es->put_mapping( $self->type_defn );

    $es->cluster_health(
        index           => $self->index,
        wait_for_status => 'green'
    );
}

#===================================
sub delete_type {
#===================================
    my $self = shift;
    $self->es->delete_mapping(
        index => $self->index,
        type  => $self->type->name
    );
}

#===================================
sub type_defn {
#===================================
    my $self  = shift;
    my $type  = $self->type;
    my $ascii = $type->ascii_folding ? 'ascii_' : '';
    return {
        index             => $self->index,
        type              => $type->name,
        _all              => { enabled => 0 },
        _source           => { enabled => 1, compress => 1 },
        dynamic_templates => [ {
                rank => {
                    path_match => 'rank.*',
                    mapping    => {
                        store => 'yes',
                        type  => 'integer'
                    }
                }
            }
        ],
        properties => {
            tokens => {
                type   => 'multi_field',
                fields => {
                    tokens => {
                        type     => 'string',
                        analyzer => $ascii . 'std',
                        store    => 'yes'
                    },
                    ngram => {
                        type            => 'string',
                        index_analyzer  => $ascii . 'edge_ngram',
                        search_analyzer => $ascii . 'std',
                    },
                }
            },
            label => {
                type  => 'string',
                index => 'not_analyzed',
                store => 'yes'
            },
            rank     => { type => 'object',    store => 'no' },
            location => { type => 'geo_point', store => 'yes' },
            %{ $type->custom_fields },
        }
    };
}

#===================================

=head1 NAME

ElasticSearchX::Autocomplete::Indexer::Type

=head1 DESCRIPTION

To follow

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
