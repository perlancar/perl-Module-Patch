package My::Target::patch::p2;

use parent qw(Module::Patch);

our %config;

sub patch_data {
    return {
        versions => {
            '0.12' => {
                subs => {
                    foo => sub { "foo from p2" },
                },
            },
        },
    };
}

1;
# ABSTRACT: Patch module for My::Target
