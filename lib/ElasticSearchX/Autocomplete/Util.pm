package ElasticSearchX::Autocomplete::Util;

use strict;
use warnings FATAL => 'all', NONFATAL => 'redefine';

use Carp;
require Exporter;
our @ISA = 'Exporter';

our @EXPORT_OK = qw(_params _debug _create_accessors _try_cache cache_key);

#===================================
sub _params {
#===================================
    my $proto = shift;
    my %params = ref $_[0] eq 'HASH' ? ( %{ $_[0] } ) : @_;
    return ( $proto, \%params );
}

#===================================
sub _debug {
#===================================
    my $self = shift;
    return unless $self->{_debug} >= shift();
    my @parts = @_;
    my $msg   = '';
    for my $v (@parts) {
        if ( ref $v ) {
            $v = $self->JSON->encode($v);
            utf8::decode($v);
        }
        $msg .= $v;
    }
    print STDERR "$msg\n";
}

#===================================
sub cache_key {
#===================================
    my $self   = shift;
    my $params = shift;
    my $JSON   = $self->JSON;
    $JSON->canonical(1);
    my $key = eval { $JSON->encode($params) };
    $JSON->canonical(0);
    croak( $@ || 'Unknown error while encoding cache key' )
        unless $key;
    $key =~ tr/ /_/;
    return $key;
}

#===================================
sub _try_cache {
#===================================
    my $self    = shift;
    my $method  = shift;
    my $params  = shift;
    my $as_json = shift;

    my ( $cache_key, $json );

    my $cache = $self->cache;
    my $JSON  = $self->JSON;

    if ($cache) {
        $cache_key = $self->cache_key($params);
        $self->_debug( 1, "Retrieve from cache: ", $cache_key );
        $json = $cache->($cache_key);
        if ($json) {
            if ( $json ne 'UNDEF' ) {
                $self->_debug( 1, " - Found in cache" );
                return $as_json ? $json : $JSON->decode($json);
            }
            $self->_debug( 1, " - Found UNDEF in cache" );
            return undef;
        }

        $self->_debug( 1, " - Not found in cache" );
    }

    my $result = $self->$method($params);
    $self->_debug( 2, "Results: ", $result || 'UNDEF' );
    unless ($result) {
        $self->_debug( 1, " - Saving UNDEF to cache" );
        $cache->( $cache_key, 'UNDEF' );
        return undef;
    }

    $json = $JSON->encode($result)
        if $as_json || $cache;

    if ($cache) {
        $self->_debug( 1, " - Saving to cache" );
        $cache->( $cache_key, $json );
    }

    return $as_json ? $json : $result;

}

#===================================
sub _create_accessors {
#===================================
    my $class = shift;
    for (@_) {
        my ( $name, $default ) = @$_;
        $default ||= 0;
        eval <<SUB or croak $@;
            sub ${class}::${name} {
                my \$self = shift;
                if (\@_) { \$self->{_$name} = shift() }
                return defined \$self->{_$name} ? \$self->{_$name} : $default;
            }
            1;
SUB

    }
}

=head1 NAME

ElasticSearchX::Autocomplete::Util

=head1 DESCRIPTION

No user servicable parts in here.

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
