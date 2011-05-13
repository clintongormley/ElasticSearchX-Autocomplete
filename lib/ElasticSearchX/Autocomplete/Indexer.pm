package ElasticSearchX::Autocomplete::Indexer;

use strict;
use warnings;
use Carp;

use ElasticSearchX::Autocomplete::Util qw(_create_accessors _params _debug);
use ElasticSearchX::Autocomplete::Indexer::Type();

__PACKAGE__->_create_accessors(
    ['debug'],
    ['JSON'],
    ['cleanup'],
    ['index'],
    ['types'],
    [ 'es',    q(croak "Missing required param 'es'") ],
    [ 'alias', q(croak "Missing required param 'alias'") ],
);

#===================================
sub new {
#===================================
    my ( $proto, $params ) = _params(@_);
    my $class = ref $proto || $proto;

    my $self = { _cleanup => 1, _debug => 0 };
    bless $self, $class;

    my $edit = delete $params->{edit};
    $self->$_( $params->{$_} ) for keys %$params;

    $self->_reopen if $edit;

    return $self;
}

#===================================
sub init {
#===================================
    my $self  = shift;
    my $index = $self->index;

    unless ($index) {
        my $es = $self->es;
        $index = $self->alias . '_' . time;

        $self->_debug( 1, "Creating index ", $index );
        $es->create_index( index => $index, %{ $self->index_defn } );
        $es->cluster_health(
            index           => $index,
            wait_for_status => 'green'
        );
        $self->index($index);
    }
    return $index;
}

#===================================
sub _reopen {
#===================================
    my $self  = shift;
    my $alias = $self->alias;
    my $index = $self->es->get_aliases->{aliases}{$alias}[0]
        or croak "Cannot edit existing index - Alias '$alias' doesn't exist";
    $self->cleanup(0);
    $self->index($index);
}

#===================================
sub deploy {
#===================================
    my ( $self, $params ) = _params(@_);

    $params = {
        replicas => '0-all',
        optimize => 1,
        %$params
    };

    my $index = $self->index or croak "No index to deploy";
    my $es = $self->es;

    if ( $params->{optimize} ) {
        $self->_debug( 1, 'Optimizing index' );
        $es->optimize_index( index => $index, max_num_segments => 1 );
    }
    if ( my $replicas = $params->{replicas} ) {
        $self->_debug( 1, 'Setting replicas to: ', $replicas );

        $es->update_index_settings(
            index    => $index,
            settings => { auto_expand_replicas => $replicas },
        );
        $es->cluster_health(
            index           => $index,
            wait_for_status => 'green'
        );
    }

    my $alias = $self->alias;
    my $old = $es->get_aliases( index => $alias )->{aliases}{$alias}[0];
    if ( !$old or $old ne $index ) {
        my @actions = { add => { index => $index, alias => $alias } };

        if ($old) {
            unshift @actions,
                { remove => { index => $old, alias => $alias } };
        }

        $self->cleanup(0);

        $self->_debug( 1, "Updating alias '$alias' to point to: ", $index );
        $es->aliases( actions => \@actions );
        if ($old) {
            $self->_debug( 1, "Deleting old index: ", $old );
            $es->delete_index( index => $old );
        }
    }
    return 1;
}

#===================================
sub type {
#===================================
    my $self = shift;

    my $name = shift or croak "Missing type name";
    my $type = $self->types->{$name} or croak "Unknown type '$name'";

    return ElasticSearchX::Autocomplete::Indexer::Type->new(
        es    => $self->es,
        debug => $self->debug,
        type  => $type,
        JSON => $self->JSON,
        index => $self->init
    );
}

#===================================
sub delete {
#===================================
    my $self  = shift;
    my $index = $self->index
        or croak "No index set. Did you mean to 'edit' the existing index?";

    $self->_debug( 1, "Deleting index: ", $index );
    $self->es->delete_index( index => $index );
    $self->index(undef);
}

#===================================
sub index_defn {
#===================================
    my $self = shift;
    return {
        settings => {
            index => {
                number_of_shards   => 1,
                number_of_replicas => 0,
                refresh_interval   => -1,
            },
            analysis => {
                filter => {
                    edge_ngram => {
                        type     => 'edgeNGram',
                        min_gram => 1,
                        max_gram => 20,
                        side     => 'front',
                    },
                },
                analyzer => {
                    std => {
                        type      => 'custom',
                        tokenizer => 'standard',
                        filter => [ 'standard', 'lowercase' ]
                    },
                    ascii_std => {
                        type      => 'custom',
                        tokenizer => 'standard',
                        filter => [ 'standard', 'lowercase', 'asciifolding' ]
                    },
                    edge_ngram => {
                        type      => 'custom',
                        tokenizer => 'standard',
                        filter => [ 'standard', 'lowercase', 'edge_ngram' ]
                    },
                    ascii_edge_ngram => {
                        type      => 'custom',
                        tokenizer => 'standard',
                        filter    => [
                            'standard',     'lowercase',
                            'asciifolding', 'edge_ngram'
                        ]
                    }
                }
            }
        }
    };
}

#===================================
sub DESTROY {
#===================================
    my $self  = shift;
    my $index = $self->index;
    if ( $index && $self->cleanup ) {
        $self->_debug( 1, "Auto-deleting index: ", $index );
        $self->es->delete_index( index => $index );
    }
}


=head1 NAME

ElasticSearchX::Autocomplete::Indexer

=head1 DESCRIPTION

To follow

=head1 SEE ALSO

L<ElasticSearchX::Autocomplete>, L<http://www.elasticsearch.org>

=head1 AUTHOR

Clinton Gormley, E<lt>clinton@traveljury.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Clinton Gormley

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.


=cut

1
