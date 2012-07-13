package My::Target::patch::p3;

use parent qw(Module::Patch);

our %config;

sub patch_data {
    return {
        versions => {
            '0.12' => {
                subs => {
                    bar => sub { "bar from p3" },
                },
            },
        },
    };
}

1;
# ABSTRACT: Patch module for My::Target
