package My::Target::patch::p3;

use parent qw(Module::Patch);

our %config;

sub patch_data {
    return {
        v => 2,
        patches => [
            {
                action => 'wrap',
                mod_version => '0.12',
                sub_name => 'bar',
                code => sub { "bar from p3" },
            },
        ]
    };
}

1;
# ABSTRACT: Patch module for My::Target
