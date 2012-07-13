#!perl

use 5.010;
use strict;
use warnings;
use Test::Exception;
use Test::More 0.96;

use FindBin '$Bin';
use lib "$Bin/lib";

use Module::Load;

sub use_ {
    my $mod = shift;
    load $mod;
    if (@_) {
        $mod->import(@_);
    } else {
        $mod->import;
    }
}

sub no_ {
    my $mod = shift;
    $mod->unimport;
}

throws_ok { use_ "My::Target::patch::cat1", -load_target=>0 } qr/before/,
    'target module must be loaded before patch module (-load_target=0)';

subtest "version matching" => sub {
    my @tests = (
        ['1.23', '1.23', 1],
        ['1.24', '1.23', 0],
        ['1.24', '1.23 1.24', 1],
        ['1.25', '1.23 1.24', 0],
        ['1.25', '1.23 1.24 1.25', 1],
        ['2.01', '1.23 1.24 1.25', 0],
        ['2.01', '1.23 1.24 1.25 /^2[.].+$/', 1],
     );
    for my $t (@tests) {
        my $res = Module::Patch::__match_v($t->[0], $t->[1]);
        if ($t->[2]) {
            ok($res, "'$t->[0]' matches '$t->[1]'");
        } else {
            ok(!$res, "'$t->[0]' doesn't match '$t->[1]'");
        }
    }
};

throws_ok { use_ "My::Target::patch::cat1", -zzz=>0 } qr/unknown/i,
    'unknown option -> dies';

lives_ok { use_ "My::Target::patch::cat1" } 'patch module can be loaded';
is(My::Target::foo(), "foo from My::Target::patch::cat1", "subroutine patched");
is($My::Target::patch::cat1::config{-v1}, 10, "default config set");
no_ "My::Target::patch::cat1";

throws_ok { use_ "My::Target::patch::unknownsub" } qr/unknown/i,
    'unknown sub -> dies';

use_ "My::Target::patch::cat1", -v1 => 100;
is($My::Target::patch::cat1::config{-v1}, 100, "setting config works");
no_ "My::Target::patch::cat1";

is(My::Target::foo(), "foo from My::Target", "unimport works");

throws_ok { use_ "My::Target::patch::cat1", -v3=>1 } qr/unknown/i,
    'unknown config -> dies';

throws_ok { use_ "My::Target::patch::cat2" } qr/version/i,
    'unknown version -> dies';
lives_ok { use_ "My::Target::patch::cat2", -on_unknown_version=>'ignore' }
    '-on_unknown_version=>ignore (1)';
is(My::Target::foo(), "foo from My::Target",
   "-on_unknown_version=>ignore (2, subroutine not patched)");

# XXX -on_unknown_version 'warn'
# XXX -on_unknown_version 'force'

# different sub won\'t conflict'
use_ "My::Target::patch::cat1";
use_ "My::Target::patch::cat4";
is(My::Target::foo(), "foo from My::Target::patch::cat1", "subroutine patched");
is(My::Target::bar(), "bar from My::Target::patch::cat4", "subroutine patched");
no_ "My::Target::patch::cat1";
no_ "My::Target::patch::cat4";

use_ "My::Target::patch::cat1";
throws_ok { use_ "My::Target::patch::cat3" } qr/conflict/i,
    'conflict';
no_ "My::Target::patch::cat1";

use_ "My::Target::patch::cat1";
lives_ok { use_ "My::Target::patch::cat3", -on_conflict=>'ignore' }
    '-on_conflict=>ignore (1)';
is(My::Target::foo(), "foo from My::Target::patch::cat1",
   "-on_conflict=>ignore (2, subroutine patch intact)");
no_ "My::Target::patch::cat1";

# XXX -on_conflict 'warn'
# XXX -on_conflict 'force'

DONE_TESTING:
done_testing();
