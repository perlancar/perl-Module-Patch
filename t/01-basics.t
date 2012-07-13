#!perl

use 5.010;
use strict;
use warnings;
use FindBin '$Bin';
use lib "$Bin/lib";

use Capture::Tiny qw(capture);
use Module::Load;
use Test::Exception;
use Test::More 0.96;

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

throws_ok { use_ "My::Target::patch::p1", -load_target=>0 } qr/before/,
    'target module must be loaded before patch module (-load_target=0)';

# by this time, Module::Patch is already loaded, so we can test its routines
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

subtest "patch module config (left as default)" => sub {
    lives_ok { use_ "My::Target::patch::p1" } 'load ok';
    is(My::Target::foo(), "foo from p1", "sub patched");
    is($My::Target::patch::p1::config{-v1}, 10, "default config set");
    no_ "My::Target::patch::p1";
};
is(My::Target::foo(), "original foo", "unimport works");

subtest "patch module config (set)" => sub {
    use_ "My::Target::patch::p1", -v1 => 100;
    is($My::Target::patch::p1::config{-v1}, 100, "setting works");
    no_ "My::Target::patch::p1";
};

throws_ok { use_ "My::Target::patch::p1", -v3=>1 } qr/unknown/i,
    'unknown patch module config -> dies';

throws_ok { use_ "My::Target::patch::unknownsub" } qr/unknown/i,
    'unknown target sub -> dies';

throws_ok { use_ "My::Target::patch::unknownver" } qr/version/i,
    'unknown target module version -> dies';

subtest '-on_unknown_version => ignore' => sub {
    lives_ok { use_ "My::Target::patch::unknownver",
                   -on_unknown_version=>'ignore' } 'load ok';
    is(My::Target::foo(), "original foo", "sub not patched");
    no_ "My::Target::patch::unknownver";
};

subtest '-on_unknown_version => warn' => sub {
    my ($stdout, $stderr, @result) = capture {
        lives_ok { use_ "My::Target::patch::unknownver",
                       -on_unknown_version=>'warn' } 'load ok';
    };
    like($stderr, qr/unknown/i, 'warning emitted');
    is(My::Target::foo(), "original foo", "sub not patched");
    no_ "My::Target::patch::unknownver";
};

subtest '-on_unknown_version => force' => sub {
    my ($stdout, $stderr, @result) = capture {
        lives_ok {use_ "My::Target::patch::unknownver",
                      -on_unknown_version=>'force'} 'load ok';
    };
    like($stderr, qr/unknown.+patching anyway/i, 'warning emitted');
    is(My::Target::foo(), "foo from unknownver", "sub patched");
    no_ "My::Target::patch::unknownver";
};

subtest "different subs won't conflict" => sub {
    use_ "My::Target::patch::p1";
    use_ "My::Target::patch::p3";
    is(My::Target::foo(), "foo from p1", "sub foo patched");
    is(My::Target::bar(), "bar from p3", "sub bar patched");
    no_ "My::Target::patch::p1";
    no_ "My::Target::patch::p3";
};

subtest "conflict" => sub {
    use_ "My::Target::patch::p1";
    throws_ok { use_ "My::Target::patch::p2" } qr/conflict/i,
        'load fails';
    no_ "My::Target::patch::p1";
};

subtest "-on_conflict => ignore" => sub {
    use_ "My::Target::patch::p1";
    lives_ok { use_ "My::Target::patch::p2", -on_conflict=>'ignore' }
        'load ok';
    is(My::Target::foo(), "foo from p1", "sub foo patched by p1");
    no_ "My::Target::patch::p1";
};

subtest "-on_conflict => warn" => sub {
    use_ "My::Target::patch::p1";
    my ($stdout, $stderr, @result) = capture {
        lives_ok { use_ "My::Target::patch::p2", -on_conflict=>'warn' }
            'load ok';
    };
    like($stderr, qr/conflict/i, 'warning emitted');
    is(My::Target::foo(), "foo from p1", "sub foo patched by p1");
    no_ "My::Target::patch::p1";
};

subtest "-on_conflict => warn" => sub {
    use_ "My::Target::patch::p1";
    is(My::Target::foo(), "foo from p1", "sub foo patched by p1");
    my ($stdout, $stderr, @result) = capture {
        lives_ok { use_ "My::Target::patch::p2", -on_conflict=>'force' }
            'load ok';
    };
    like($stderr, qr/conflict/i, 'warning emitted');
    is(My::Target::foo(), "foo from p2", "sub foo now patched by p2");
    no_ "My::Target::patch::p2";
    is(My::Target::foo(), "foo from p1", "p1 patch restored");
    no_ "My::Target::patch::p1";
};

DONE_TESTING:
done_testing();
