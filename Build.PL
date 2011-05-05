use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name       => 'ElasticSearchX::Autocomplete',
    license           => 'perl',
    dist_author       => q{Clinton Gormley <drtech@cpan.org>},
    dist_version_from => 'lib/ElasticSearchX/Autocomplete.pm',
    build_requires    => {
        'Test::More'      => 0,
        'Test::Exception' => 0,
    },
    add_to_cleanup     => ['ElasticSearchX-*'],
    create_makefile_pl => 'traditional',
    requires           => {
        'ElasticSearch' => '0.37',
        'JSON'          => 0,
    },
    recommends => { 'JSON::XS' => 0, },
    meta_merge => {
        resources => {
            repository =>
                'https://github.com/clintongormley/ElasticSearchX-Autocomplete/',
            bugtracker =>
                "https://github.com/clintongormley/ElasticSearchX-Autocomplete/issues",
        }
    },
);

$builder->create_build_script();
