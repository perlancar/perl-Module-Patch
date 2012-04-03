package My::Target::patch::cat2;

use parent qw(Module::Patch);

our %config;

sub patch_data {
    return {
        versions => {
            '0.13' => {
                subs => {
                    foo => sub { "foo from My::Target::patch::cat2" },
                },
            },
        },
    };
}

1;
# ABSTRACT: Patch module for My::Target
