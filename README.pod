package ElasticSearchX::Autocomplete;

use strict;
use warnings;
use Carp;

use ElasticSearch 0.28;
use Text::Unidecode;
use JSON::XS;

our $JSON    = JSON::XS->new()->utf8(1);
our $VERSION = '0.01';

=encoding utf-8

=head1 NAME

ElasticSearchX::Autocomplete - easy autocompletion with ElasticSearch

=head1 SYNOPSIS

Create an autocompleter:

    use ElasticSearchX::AutoComplete();
    my $es = ElasticSearch->new(servers=>'127.0.0.1:9200');

    my $auto = ElasticSearchX::Autocomplete->new(
        es      => $es,
        index   => 'suggest',
        type    => 'names'
    );


Index management:

    $auto->create_index();
    $auto->create_type();

    # index phrases, then:
    $auto->optimize_index()

    $auto->delete_type();
    $auto->delete_index();

Index phrases:

    $auto->index_phrases(
        query   => {
            index   => 'my_index',
            type    => 'person',
            query   => { match_all => {} }
        },
        parser  => sub {
            my $auto     = shift;
            my $doc      = shift;
            my @words    = $auto->tokenize($doc->{_source}{fullname});
            return { words => \@words };
        }
    );

Index phrases with contexts:

    $auto->index_phrases(
        query   => {
            index   => 'my_index',
            type    => 'person',
            query   => { match_all => {} }
        },
        parser  => sub {
            my $auto     = shift;
            my $doc      = shift;
            my @words    = $auto->tokenize($doc->{_source}{fullname});
            my @contexts => @{$doc->{_source}{address_books}};
            return {
                words       => \@words,
                contexts    => \@contexts
            };
        }
    );

Autocomplete:

    @suggestions = $auto->suggest('jo bl');
    # jo black
    # joe black
    # joseph bloggs

    # with context
    @suggestions = $auto->suggest('jo bl','personal');

Counts:

    $count = $auto->context_count();
    #    [
    #        { 'personal'           => 20 },
    #        { 'business'           => 18 },
    #        { 'personal friend'    => 12 },
    #        { 'business colleague' => 11 },
    #        { 'personal other'     => 8  },
    #        { 'business other'     => 7  },
    #    ]

    $count = $auto->context_count(context => 'personal');
    #    20

    $count = $auto->context_count(prefix => 'personal');
    #    [
    #        { 'personal'           => 20 },
    #        { 'personal friend'    => 12 },
    #        { 'personal other'     => 8  },
    #    ]


=head1 DESCRIPTION

C<ElasticSearchX::Autocomplete> gives you context-sensitive
autocomplete suggestions based on the frequency of those terms in your data.

=head2 What is autocomplete?

You know. Like our favourite search engine. Let's say you want to use
autocomplete on the names of people who send you emails. You have:

        Name                        Emails
        ----------------------------------
        Jon Bloggs                  8
        Jonathon Smith              15
        Maria Smythe                2
        Mark Black                  4
        Jock Bloggs                 1
        María Nuñez                 3      # Note the accents

After loading them into ElasticSearch, here are the suggestions returned for
each search phrase:

=over

=item  *

The matching terms are ranked by the frequency/count/number of emails:

    # "jo"
            jonathon smith          # most emails
            jon bloggs
            jock bloggs

=item *

But if one or more words match completely, then they appear higher in the list:

    # "jon"
            jon bloggs              # full name match 'jon'
            jonathon smith

=item *

Terms are sorted in the same order in which they appear in the original phrase:

    # "bl"
            bloggs jon
            black mark
            bloggs jock

    # "jo bl"
            jon bloggs
            jock bloggs

=item *

Accents are folded so that searches with or without accents still work:

    # "ma"
            mark black
            maría nuñez
            maria smythe

    # "maria" or "maría"
            maría nuñez
            maria smythe

=back

=head2 What does context-sensitive mean?

Perhaps your emails are organised as folders:

    /Inbox
        /Personal
            /Friends
            /Others
        /Business
            /Colleagues
            /Others

You may want to search across your whole C</Inbox> or only
in C</Inbox/Personal/Friends>.

Each of these is referred to as a C<context> and a separate frequency
is stored for each C<context>, which makes it easy to get results relevant
only to your desired context.

An email in your C<Friends> folder would have these contexts:

    @contexts = [qw(
        /Inbox
        /Inbox/Personal
        /Inbox/Personal/Friends
    )];

=head2 Why ElasticSearch?

ElasticSearch is a powerful, open source, Lucene-based, full text search server,
with a REST over HTTP interface, automatic clustering and failover, written in Java.

You can check it out here: L<http://www.elasticsearch.org>.

ElasticSearch is the magic that makes this autocomplete module work, and
work fast.  You will need an ElasticSearch server installed in order to use
this module.
See L<http://www.elasticsearch.org/tutorials/2010/07/01/setting-up-elasticsearch.html>

Your original data can come from ElasticSearch, but doesn't have to.  It
can also be loaded from a JSON file, or passed in directly to
L</"index_phrases()">.

=head1 BUILDING YOUR INDEX

The basic steps are:

    use ElasticSearchX::Autocomplete();
    my $es   = ElasticSearch->new( servers => '127.0.0.1:9200' );

    my $auto = ElasticSearchX::Autocomplete->new(
         es      => $es,
         index   => 'suggest',
         type    => 'person',
    );

C<index> is an ElasticSearch index (like a database) where you plan on storing
your autocomplete data. One index can contain many types.

C<type> is the type of data you want to store (like a table in a database), eg
C<person>, C<name>, C<location>.

Create your index (if you haven't done so already):

    $auto->create_index();

Create your type:

    $auto->create_type()

Index your phrases, for example:

    $auto->index_phrases(
        query => {
            index   => 'mydata',
            type    => 'person',
            query   => { match_all => {} },
        },
        parser => sub {
            my $auto  = shift;
            my $doc   = shift;
            my @words = split / /, $doc->{_source}{name};
            return { words => \@words };
        },
    );

Or, with contexts:

    $auto->index_phrases(
        query => {
            index   => 'mydata',
            type    => 'person',
            query   => { match_all => {} },
        },
        parser => sub {
            my $auto     = shift;
            my $doc      = shift;
            my @words    = split / /, $doc->{_source}{name}};
            my @contexts = @{$doc->{_source}{tags}};
            return {
                words    => \@words,
                contexts => \@contexts
            };
        },
    );


You can store the autocomplete data for more than one type in the same index.
If you have already created the index, then you just need to do the
C<create_type()> and C<index_phrases()> steps for each type.

Once you are ready to deploy your index, do:

    $auto->optimize_index();

And you are ready to use it!

=head1 QUERYING YOUR INDEX

    @suggestions = $auto->suggest('joe bloggs');

Or, with a context:

    @suggestions = $auto->suggest('joe bloggs','personal');

You can retrieve totals for each context:

    $total = $auto->context_count(context => 'personal');

Or the totals for all contexts with a particular prefix:

    @totals = $auto->context_count(prefix => '/Inbox');

    # { "/Inbox"                    => 10 },
    # { "/Inbox/Personal"           => 6 },
    # { "/Inbox/Personal/Friends"   => 4 },
    # { "/Inbox/Personal/Other"     => 4 },

=head1 METHODS

=head2 new()

    $auto = ElasticSearchX::Autocomplete->new(

        # required
        es      => $elastic_search_instance,
        index   => $index_name,
        type    => $type_name,

        # optional
        ascii_folding   => 1 | 0,
        match_boost     => 1,
        max_results     => 10,
        tokenizer       => sub {...},

    );

Creates an instance of L<ElasticSearchx::Autocomplete>.  See below for
details of the each parameter.

=cut

#===================================
sub new {
#===================================
    my $proto  = shift;
    my $class  = ref $proto || $proto;
    my $params = ref $_[0] eq 'HASH' ? shift() : {@_};
    my $self   = { _ascii_folding => 1, _tokenizer => \&_tokenize };

    bless $self, $class;
    $self->$_( $params->{$_} ) for keys %$params;

    return $self;
}

=head2 suggest()

    @suggestions = $auto->suggest($phrase);
    $suggestions = $auto->suggest($phrase);             # array ref

With a context:

    @suggestions = $auto->suggest($phrase,$context);
    $suggestions = $auto->suggest($phrase,$context);    # array ref

Returns a list of suggestions that match the passed in phrase.  The maximum
number of items returned can be controlled with L</"max_results()">;

See also L</"match_boost()"> and L</"ascii_folding()">.

=cut

#===================================
sub suggest {
#===================================
    my $self   = shift;
    my $phrase = shift;
    return unless defined $phrase;

    my $context = shift;
    $context = '' unless defined $context;

    my $tokenizer = $self->tokenizer;
    my @words     = $tokenizer->($phrase);
    return unless @words;

    my $results = $self->_retrieve_suggestions( $context, @words );

    my @phrases;
    my $use_ascii = $self->ascii_folding;

    my %ascii
        = $use_ascii
        ? map { $_ => unidecode($_) } @words
        : map { $_ => $_ } @words;

    for my $hit (@$results) {
        my @new_words;
        my @candidates = @{ $hit->{fields}{words} };
        my %unused
            = $use_ascii
            ? map { $_ => unidecode($_) } @candidates
            : map { $_ => $_ } @candidates;

    ORIGINAL: for my $original (@words) {
            my $ascii = $ascii{$original};
            for my $candidate ( keys %unused ) {
                if ( $unused{$candidate} =~ /^${ascii}/i ) {
                    delete $unused{$candidate};
                    push @new_words, $candidate;
                    next ORIGINAL;
                }
            }
            push @new_words, $original;
        }

        for my $candidate (@candidates) {
            push @new_words, $candidate
                if $unused{$candidate};
        }

        push @phrases, join ' ', @new_words;
    }

    return wantarray ? @phrases : \@phrases;
}

#===================================
sub _retrieve_suggestions {
#===================================
    my $self    = shift;
    my $context = shift;
    my @words   = @_;

    my $word_query = {
        bool => {
            must => [ {
                    field => {
                        'words.ngram' => join ' ',
                        map {"+$_"} @words
                    }
                }
            ],
            should => [ {
                    field => {
                        'words' => {
                            query => join( ' ', @words ),
                            boost => $self->match_boost,
                        }
                    }
                },
            ]
        }
    };

    my $results = $self->es->search(
        index => $self->index,
        type  => $self->type,

        # preference => '_local',
        query => {
            custom_score => {
                query => {
                    filtered => {
                        filter => { term => { context => $context } },
                        query  => $word_query,
                    }
                },
                script => "_score * doc['freq'].value",
            }
        },
        size   => $self->max_results,
        fields => [ 'words', 'freq' ],
    );

    return $results->{hits}{hits};
}

=head2 context_count()

    $total  = $auto->context_count( context => $context );

    # All contexts:
    @totals = $auto->context_count( max => $max_no_of_results );

    # { '/Inbox'                        => 20 },
    # { '/Inbox/Business'               => 11 },
    # { '/Inbox/Personal'               => 9  },
    # { '/Inbox/Business/Other'         => 8  },
    # { '/Inbox/Personal/Friends'       => 5  },
    # { '/Inbox/Personal/Other'         => 4  },
    # { '/Inbox/Business/Colleagues'    => 3  },

    # Contexts begining with $prefix eg '/Inbox/Personal'
    @totals = $auto->context_count(
        prefix => $prefix,
        max    => $max_no_of_results,
    );

    # { '/Inbox/Personal'               => 9  },
    # { '/Inbox/Personal/Friends'       => 5  },
    # { '/Inbox/Personal/Other'         => 4  },

C<max> defaults to C<10>.

=cut

#===================================
sub context_count {
#===================================
    my $self   = shift;
    my $params = ref $_[0] ? shift() : {@_};
    my $es     = $self->es;
    my $index  = $self->index;
    my $type   = $self->type;

    if ( defined $params->{context} ) {
        return $es->count(
            index => $index,
            type  => $type,
            term  => { context => $params->{context} }
        )->{count};
    }

    my $max = $params->{max} || 10;
    my $query
        = defined $params->{prefix}
        ? { constant_score =>
            { filter => { prefix => { context => $params->{prefix} } } } }
        : { match_all => {} };

    my $results = $es->search(
        index  => $index,
        type   => $type,
        query  => $query,
        size   => 0,
        facets => {
            context => {
                terms => {
                    field => 'context',
                    size  => $max
                }
            }
        }
    );
    my @counts = map {
        { $_->{term} => $_->{count} }
    } @{ $results->{facets}{context}{terms} };
    return wantarray ? @counts : \@counts;
}

=head2 index_phrases()

    $auto->index_phrases(
        phrases     => [],
        verbose     => 0 | 1
    );

    $auto->index_phrases(
        filename    => 'file.json',
        verbose     => 0 | 1
    );

    $auto->index_phrases(
        query       => { elasticsearch query },
        parser      => sub { parser },

        min_freq    => 1,
        max_words   => 10,
        verbose     => 0 | 1,
    )

C<index_phrases()> indexes all the phrases into the ElasticSearch autocomplete
index.

C<< verbose => 1 >> will cause some progress information to be printed out.

Phrases can either be passed in as the C<phrases> param, loaded from the JSON
file C<filename> or retrieved from an ElasticSearch index using
L</"aggregate_phrases()">.

The C<phrases> parameter (or the JSON contained in C<filename>) should have
this structure:

    [
        {
            words         => ['word','word'...],
            contexts      => {
                context_1 => $freq_1,
                context_2 => $freq_2
                ...
        },
        ...
    ]

If there are no contexts, then the structure should be:

    [
        {
            words         => ['word','word'...],
            contexts      => { '' => $freq }
        },
        ...
    ]

NOTE: Reindexing the same words will cause those words to be added, not
overwritten.  Instead you should either L</"delete_contexts()">,
L</"delete_type()"> or L</"delete_index()"> before reindexing.

=cut

#===================================
sub index_phrases {
#===================================
    my $self = shift;
    my $params = ref $_[0] ? shift() : {@_};

    my $phrases
        = $params->{phrases}
        || $params->{filename} && $self->_load_phrases( $params->{filename} )
        || $self->aggregate_phrases($params);

    my $verbose = $params->{verbose};

    my $i = 0;
    my @recs;
    my $index = $self->index;
    my $type  = $self->type;

    print "Indexing " . ( scalar @$phrases ) . " phrases\n"
        if $verbose;

    my $es = $self->es;
    for my $entry (@$phrases) {
        my ( $words, $contexts ) = @{$entry}{ 'words', 'contexts' };
        for my $context ( keys %$contexts ) {
            push @recs,
                {
                index => $index,
                type  => $type,
                data  => {
                    words   => $words,
                    context => $context,
                    freq    => $contexts->{$context}
                }
                };
            if ( ++$i % 1000 == 0 ) {
                $es->bulk_index( \@recs );
                print "$i\n"
                    if $verbose;
                @recs = ();
            }
        }
    }
    if (@recs) {
        $es->bulk_index( \@recs );
        print "$i\n"
            if $verbose;
    }

}

=head2 aggregate_phrases()

    $phrases = $auto->aggregate_phrases(
        # required
        query       => { elasticsearch query },
        parser      => sub { parser },

        # optional
        min_freq    => 1,
        max_words   => 10,
        verbose     => 0 | 1,
    );

C<aggregate_phrases()> is used to build the list of phrases and their
frequencies from an ElasticSearch query.

C<query> is the query that will be run against your ElasticSearch server
and can contain any of the parameters (except C<sort>) that would be passed to
L<ElasticSearch/"search()">.  For instance:

    query => {
        index   => 'address_book',
        type    => 'person',
        query   => { match_all => {} }
    }

See L<http://www.elasticsearch.org/guide/reference/query-dsl/> for more.

C<parser> should be a sub reference which processes each document from
ElasticSearch and returns the relevant words and contexts, for instance:

    parser => sub {
        my $auto   = shift;  # the auto completer instance
        my $doc    = shift;  # the doc from elasticsearch
        my $source = $doc->{_source};

        my @words    = $auto->tokenize($source->{name});
        my @contexts = @{$source->{tags}};
        return {
            words    => \@words,
            contexts => \@contexts
        }
    }

If no C<@contexts> are returned, then a default context of C<''> will be
used instead.

The standard L</"tokenizer()"> breaks up words on anything
that isn't a letter or an apostrophe, and lowercases all terms. You
can override this.

You can choose to not index any C<phrase/context> combinations that have a
frequency less than C<min_freq>.

The maximum number of terms in C<@words> can be controlled with C<max_words>
(default C<10>).

C<< verbose => 1 >> will cause C<aggregate_phrases()> to print out some progress
information.

=cut

#===================================
sub aggregate_phrases {
#===================================
    my $self = shift;
    my $params = ref $_[0] ? shift : {@_};

    my $query = $params->{query}
        || croak "No query passed to aggregate()";

    croak "The query cannot include a sort parameter"
        if $query->{sort};

    my $parser = $params->{parser}
        || croak "No parser callback passed to aggregate()";

    my $max       = $params->{max} || 1000;
    my $es        = $self->es;
    my $verbose   = $params->{verbose};
    my $min_freq  = $params->{min_freq} || 1;
    my $max_words = ( $params->{max_words} || 10 ) - 1;

    my %phrases;
    my $start = 0;

    my $r = $es->search(
        %$query,

        #        search_type => 'scan',
        size   => $max,
        scroll => '5m'
    );

    print "Aggregating $r->{hits}{total} records\n"
        if $verbose;

    my $total = 0;
    while (1) {
        my $hits = $r->{hits}{hits};
        last unless @$hits;

        for my $doc (@$hits) {
            my $vals = $parser->( $self, $doc );
            my @words = @{ $vals->{words} || [] };
            $#words = $max_words if @words >= $max_words;
            my $id = join "\t", sort grep { defined && length } @words;
            next unless length $id;

            my @contexts = @{ $vals->{contexts} || [] };
            @contexts = '' unless @contexts;
            $phrases{$id}{words} ||= \@words;
            $phrases{$id}{contexts}{$_}++ for @contexts;
        }

        $total += @$hits;
        print "$total\n"
            if $verbose;

        $r = $es->scroll( scroll_id => $r->{_scroll_id}, scroll => '5m' );
    }

    if ( $min_freq > 1 ) {
        for my $id ( keys %phrases ) {
            my $contexts = $phrases{$id}{contexts};
            for my $context ( keys %$contexts ) {
                delete $contexts->{$context}
                    if $contexts->{$context} < $min_freq;
            }
            delete $phrases{$id}
                unless %$contexts;
        }
    }

    return [ values %phrases ];
}

=head2 save_phrases()

    $auto->save_phrases(
        # required
        filename    => 'output.json',
        query       => { elasticsearch query },
        parser      => sub { parser },

        # optional
        min_freq    => 1,
        max_words   => 10,
        verbose     => 0 | 1,

    )

C<save_phrases()> calls L</"aggregate_phrases()"> and saves the output
to C<filename>.

=cut

#===================================
sub save_phrases {
#===================================
    my $self     = shift;
    my $params   = ref $_[0] ? shift : {@_};
    my $filename = $params->{filename}
        or croak "No filename passed to save_phrases()";
    my $phrases = $self->aggregate_phrases($params);
    open my $fh, '>', $filename
        or croak "Couldn't open $filename for writing: $!";
    binmode $fh;
    print $fh $JSON->encode($phrases)
        or croak "Couldn't write phrase data to $filename: $!";
    close $fh
        or croak "Couldn't close $filename: $!";
    return $filename;
}

#===================================
sub _load_phrases {
#===================================
    my $self     = shift;
    my $filename = shift;
    open my $fh, '<', $filename
        or croak "Couldn't open $filename for reading: $!";
    binmode $fh;
    my $data = join '', <$fh>;
    croak "Couldn't read from $filename: $!"
        unless defined $data;
    return $JSON->decode($data);
}

=head2 create_index()

    $auto->create_index()

Creates the index set in L</"index()"> or throws an error if it already exists.
An index can contain more than one L</"type()">

=cut

#===================================
sub create_index {
#===================================
    my $self  = shift;
    my $es    = $self->es;
    my $index = $self->index;
    $es->create_index(
        index    => $index,
        settings => {
            index => {
                number_of_shards   => 1,
                number_of_replicas => 0,
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
                        filter    => [ 'standard', 'lowercase' ]
                    },
                    ascii_std => {
                        type      => 'custom',
                        tokenizer => 'standard',
                        filter => [ 'standard', 'lowercase', 'asciifolding' ]
                    },
                    edge_ngram => {
                        type      => 'custom',
                        tokenizer => 'standard',
                        filter    => [ 'standard', 'lowercase', 'edge_ngram' ]
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
    );
    $es->cluster_health( index => $self->index, wait_for_status => 'green' );
    return $index;
}

=head2 delete_index()

    $auto->delete_index()

Deletes the index set in L</"index()"> or throws an error if it doesn't exist.
It also deletes all of the data and types in the index.

=cut

#===================================
sub delete_index {
#===================================
    my $self = shift;
    my $es   = $self->es;
    $es->delete_index( index => $self->index );
    $es->cluster_health( wait_for_status => 'yellow' );
    return;
}

=head2 optimize_index()

    $auto->optimize_index()

Optimizes the index for fast retrieval.  Depending on the amount of data
contained in the index, this may take some time.

This should be called once all of the phrases have been indexed, and before
the index is used in live.

=cut

#===================================
sub optimize_index {
#===================================
    my $self     = shift;
    my $params   = ref $_[0] ? shift() : {@_};
    my $replicas = $params->{replicas} || 0;

    my $es = $self->es;
    $es->optimize_index( index => $self->index, max_num_segments => 1 );
    $es->update_index_settings(

        # set divisor
        # settings => { auto_expand_replicas=> '0-all'}
        settings => { number_of_replicas => $replicas }
    );
    return;
}

=head2 create_type()

    $auto->create_type()

Creates the L</"type()"> where a C<type> is like a table in a database.
Throws an error if the type already exists.

=cut

#===================================
sub create_type {
#===================================
    my $self = shift;

    my $es = $self->es;
    my $ascii = $self->ascii_folding ? 'ascii_' : '';

    $es->put_mapping(
        index      => $self->index,
        type       => $self->type,
        _all       => { enabled => 0 },
        _source    => { enabled => 0 },
        properties => {
            words => {
                type   => 'multi_field',
                fields => {
                    words => {
                        type     => 'string',
                        analyzer => $ascii . 'std',
                        store    => 'yes'
                    },
                    ngram => {
                        type     => 'string',
                        analyzer => $ascii . 'edge_ngram'
                    },
                }
            },
            freq    => { type => 'integer', store => 'yes' },
            context => { type => 'string',  index => 'not_analyzed' },
        }
    );
    $es->cluster_health( index => $self->index, wait_for_status => 'green' );
    return $self->type;
}

=head2 delete_type()

    $auto->delete_type()

Deletes the L</"type()"> and all the data stored in that type.
Throws an error if the type doesn't exist.


=cut

#===================================
sub delete_type {
#===================================
    my $self = shift;
    $self->es->delete_mapping( index => $self->index, type => $self->type );
    return;
}

=head2 delete_contexts()

    # all contexts
    $auto->delete_contexts();

    # all @contexts
    $auto->delete_contexts( contexts => \@contexts );

    # all contexts with $prefix
    $auto->delete_contexts( prefix => $prefix )

Deletes all contexts in C<$contexts> or all contexts which begin with
C<$prefix>.

=cut

#===================================
sub delete_contexts {
#===================================
    my $self = shift;
    my $params = ref $_[0] ? shift() : {@_};

    my $filter
        = $params->{contexts} ? { terms  => $params->{contexts} }
        : $params->{prefix}   ? { prefix => $params->{prefix} }
        :                       undef;

    if ($filter) {
        my $es    = $self->es;
        my $index = $self->index;
        $es->delete_by_query(
            index          => $index,
            type           => $self->type,
            constant_score => { filter => $filter }
        );
        $es->refresh_index( index => $index );
    }
    else {
        $self->delete_type();
        $self->create_type();
    }
}

=head2 es()

    $es_instance = $auto->es($es_instance);

Getter/setter for the L<ElasticSearch> instance, which is a required parameter.

=head2 index()

    $index = $auto->index($index)

Getter/setter for the C<index> name, which is the index (like a database)
where ElasticSearch will store the autocomplete data.

=head2 type()

    $type = $auto->type($type)

Getter/setter for the C<type> name which is like a table in a database.
A type could represent different types of phrases to autocomplete,
eg C<name>, C<city>, C<language> etc

=cut

#===================================
sub es { _accessor( 'es', @_ ) || croak "No ElasticSearch instance set" }
sub index { _accessor( 'index', @_ ) || croak "No index has been set" }
sub type  { _accessor( 'type',  @_ ) || croak "No index has been set" }
#===================================

=head2 tokenize()

    @words = $auto->tokenize('$phrase');

Returns a list of words as tokenized by L</"tokenizer()">. By default
it lowercases the phrase, and splits it into words on anything which isn't
a letter or an apostrophe. Only unique words are returned.

=head1 PROPERTIES

=head2 tokenizer()

    $tokenizer = $auto->tokenizer( sub { } )

Getter/setter for the tokenizer used by C<ElasticSearchX::Autocomplete>. The
C<tokenizer> is used by L</"aggregate_phrases()"> and by L</"suggest()">.

The value should be a sub ref, eg, the default implementation:

    $auto->tokenizer(
        my $str = shift;
        my %seen;
        my @words;
        for my $word ( grep {$_} split /(?:[^\w']|\d)+/, lc $str ) {
            push @words, $word
                unless $seen{$word}++;
        }
        return @words;
    )

=cut

#===================================
sub tokenize { shift->{_tokenizer}->(shift) }
#===================================

#===================================
sub _tokenize {
#===================================
    my $str = shift;
    my %seen;
    my @words;
    for my $word ( grep {$_} split /(?:[^\w']|\d)+/, lc $str ) {
        push @words, $word
            unless $seen{$word}++;
    }
    return @words;
}

=head2 ascii_folding()

    $bool = $auto->ascii_folding($bool)

If true (the default), all phrases will be ascii-folded, ie phrases with
accents will be treated as though they don't have accents, eg:

    "maria" == "maría"

This should be set before the type is created (with L</"create_type()">).

=head2 max_results()

    $max = $auto->max_results($max)

The maximum number of suggestions that will be returned by L</"suggest()">,
defaults to 10.

=head2 max_words()

    $max = $auto->max_words($max)

The maximum number of words/terms (default 10) that will be returned for each
phrase in L</"aggregate_phrases()">.

For instance, if the phrase C<"The quick brown fox jumped over the lazy dog">
with < C<max_words> value of 5 would return C<"brown dog fox jumped lazy">.

=head2 match_boost()

    $boost = $auto->match_boost($boost)

A word that matches a whole word is "boosted" (ie ranked more highly) than
a word that only partially matches.

For instance: C<"jon"> would rank C<"jon"> more highly than C<"jonathon">.

However, the frequency/count for the phrase is also factored into the ranking.

How much a whole-word match counts can be tuned with C<match_boost()> where
a value of C<0> would stop it counting at all.  The default is C<1>.

=cut

#===================================
sub ascii_folding { _accessor( 'ascii_folding', @_ ) }
sub max_results   { _accessor( 'max_results',   @_ ) || 10 }
sub max_words     { _accessor( 'max_words',     @_ ) || 10 }
sub match_boost   { _accessor( 'match_boost',   @_ ) || 1 }
sub tokenizer     { _accessor( 'tokenizer',     @_ ) }
#===================================

#===================================
sub _accessor {
#===================================
    my $key  = shift;
    my $self = shift;
    if (@_) {
        $self->{"_$key"} = shift;
    }
    return $self->{"_$key"};
}

=head1 SEE ALSO

L<ElasticSearch>, L<http://www.elasticsearch.org>

=head1 TODO

You tell me :)

=head1 BUGS

This is a beta module, so there will be bugs, and the API is likely to
change in the future, as the API of ElasticSearch itself changes.

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
