package My::Target::patch::unknownver;

use parent qw(Module::Patch);

our %config;

sub patch_data {
    return {
        versions => {
            '0.13' => {
                subs => {
                    foo => sub { "foo from unknownver" },
                },
            },
        },
    };
}

1;
# ABSTRACT: Patch module for My::Target
