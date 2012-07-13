package My::Target::patch::unknownsub;

use parent qw(Module::Patch);

our %config;

sub patch_data {
    return {
        versions => {
            '0.12' => {
                subs => {
                    qux => sub { "qux from unknownsub" },
                },
            },
        },
    };
}

1;
# ABSTRACT: Patch module for My::Target
