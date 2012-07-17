package My::Target::patch::p1;

use parent qw(Module::Patch);

our %config;

sub patch_data {
    return {
        v => 2,
        config => {
            -v1 => {default=>10},
            -v2 => {},
        },
        patches => [
            {
                action => 'wrap',
                mod_version => ['0.11', '0.12'],
                sub_name => 'foo',
                code => sub { "foo from p1" },
            },
        ],
    };
}

1;
# ABSTRACT: Patch module for My::Target
