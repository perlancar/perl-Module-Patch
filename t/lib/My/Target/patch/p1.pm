package My::Target::patch::p1;

use parent qw(Module::Patch);

our %config;

sub patch_data {
    return {
        config => {
            -v1 => {default=>10},
            -v2 => {},
        },
        versions => {
            '0.11 0.12' => {
                subs => {
                    foo => sub { "foo from p1" },
                },
            },
        },
    };
}

1;
# ABSTRACT: Patch module for My::Target
