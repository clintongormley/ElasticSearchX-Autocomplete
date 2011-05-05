package ElasticSearchX::Autocomplete;

use strict;
use warnings;
use Carp;

use ElasticSearch 0.37;
use ElasticSearchX::Autocomplete::Util qw(_create_accessors _params );
use ElasticSearchX::Autocomplete::Type();
use JSON();

our $JSON    = JSON->new()->utf8(1);
our $VERSION = '0.01';

__PACKAGE__->_create_accessors(
    ['cache'],
    ['debug'],
    ['JSON'],
    [ 'es',    q(croak "Missing required param 'es'") ],
    [ 'index', q(croak "Missing required param 'index'") ],

);

#===================================
sub new {
#===================================
    my ( $proto, $params ) = _params(@_);
    my $class = ref $proto || $proto;

    my $self = { _debug => 0, _types => {}, _JSON => $JSON };
    bless $self, $class;

    my $types = delete $params->{types} || {};
    $self->$_( $params->{$_} ) for keys %$params;
    $self->add_type( $_, $types->{$_} ) for keys %$types;

    return $self;
}

#===================================
sub types { shift->{_types} }
#===================================

#===================================
sub type {
#===================================
    my $self = shift;
    my $type = shift or croak "No type name passed to type()";
    return $self->{_types}{$type} || croak "Unknown type '$type'";
}

#===================================
sub add_type {
#===================================
    my $self = shift;
    my $name = shift;
    my $defn = shift || {};
    my $type = ElasticSearchX::Autocomplete::Type->new(
        name => $name,
        ( map { $_ => $self->$_ } qw(es index cache JSON debug) ), %$defn
    );
    return $self->{_types}{$name} = $type;
}

#===================================
sub indexer {
#===================================
    my ( $self, $params ) = _params(@_);

    require ElasticSearchX::Autocomplete::Indexer;
    return ElasticSearchX::Autocomplete::Indexer->new(
        alias => $self->index,
        ( map { $_ => $self->$_ } qw(es debug types JSON) ),
        %$params,
    );
}

=head1 NAME

ElasticSearchX::Autocomplete - Efficient autocomplete with term frequency
and geolocation

=head1 VERSION

Version 0.01 - alpha

=head1 DESCRIPTION

C<ElasticSearchX::Autocomplete> helps you to build autocomplete indexes
from your data, taking term frequency and (optionally) geolocation
into account.

This is an alpha module, and still requires documentation and tests. Here
be dragons.

=head1 SEE ALSO

L<ElasticSearch>, L<http://www.elasticsearch.org>

=head1 BUGS

If you have any suggestions for improvements, or find any bugs, please report
them to L<https://github.com/clintongormley/ElasticSearchX-Autocomplete/issues>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 AUTHOR

Clinton Gormley, E<lt>clinton@traveljury.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Clinton Gormley

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.


=cut

1
