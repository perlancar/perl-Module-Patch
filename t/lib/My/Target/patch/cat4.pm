package My::Target::patch::cat4;

use parent qw(Module::Patch);

our %config;

sub patch_data {
    return {
        versions => {
            '0.12' => {
                subs => {
                    bar => sub { "bar from My::Target::patch::cat4" },
                },
            },
        },
    };
}

1;
# ABSTRACT: Patch module for My::Target
