package My::Target::patch::cat3;

use parent qw(Module::Patch);

our %config;

sub patch_data {
    return {
        versions => {
            '0.12' => {
                subs => {
                    foo => sub { "foo from My::Target::patch::cat3" },
                },
            },
        },
    };
}

1;
# ABSTRACT: Patch module for My::Target
