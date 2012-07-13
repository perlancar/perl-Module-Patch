package Module::Patch;

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use Carp;
use Module::Load;
use Module::Loaded;
use Monkey::Patch qw(:all);

# VERSION

# match versions specification string, e.g. whether target '2.07' is in '1.23
# 1.24 /^2\..+$/' (answer: it is)
sub __match_v {
    my ($target, $spec) = @_;

    my @v = split /[,;]?\s+/, $spec;
    for (@v) {
        if (s!^/(.*)/$!$1!) {
            return 1 if $target ~~ /$_/;
        } else {
            return 1 if $target eq $_;
        }
    }
    0;
}

my %applied_patches; # key = targetmod, value = [patchmod1, ...]

sub import {
    no strict 'refs';
    no warnings; # W lines generates warning

    my ($self, %args) = @_;
    my $handle = \%{"$self\::handle"}; #W

    my $pre = $self; # error message prefix

    # already patched, ignore
    return if keys %$handle;

    my $on_uv = 'die';
    if (exists $args{-on_unknown_version}) {
        $on_uv = $args{-on_unknown_version};
        delete $args{-on_unknown_version};
    }
    my $on_c = 'die';
    if (exists $args{-on_conflict}) {
        $on_c = $args{-on_conflict};
        delete $args{-on_conflict};
    }
    my $load = 1;
    if (exists $args{-load_target}) {
        $load = $args{-load_target};
        delete $args{-load_target};
    }

    my $target = $self;
    $target =~ s/(?<=\w)::patch::\w+$//
        or die "BUG: Bad patch module name '$target', it should ".
            "end with '::patch::something'";

    unless (is_loaded $target) {
        if ($load) {
            load $target;
        } else {
            croak "FATAL: $pre: $target is not loaded, please 'use $target' ".
                "before patching";
        }
    }

    my $target_ver = ${"$target\::VERSION"};
    defined($target_ver) && length($target_ver)
        or croak "FATAL: $pre: Target module '$target' does not have \$VERSION";

    my $pdata = $self->patch_data;
    ref($pdata) eq 'HASH'
        or die "BUG: patch_data() does not return a hash";

    # read patch module's configs
    my $pcdata = $pdata->{config} // {};
    my $config = \%{"$self\::config"};
    while (my ($k, $v) = each %$pcdata) {
        $config->{$k} = $v->{default};
        if (exists $args{$k}) {
            $config->{$k} = $args{$k};
            delete $args{$k};
        }
    }
    # Log::Any::App not init() yet
    #$log->tracef("Patch module config: %s", $config);
    #use Data::Dump; dd $config;

    if (%args) {
        croak join(
            "",
            "FATAL: $pre: Unknown option: ", join(", ", keys %args), ". ",
            "Please consult Module::Patch documentation for available ",
            "options."
        );
    }

    # check version

    my $vers = $pdata->{versions};
    ref($vers) eq 'HASH'
        or die "BUG: patch data must contain 'versions' and it must be a hash";

    # check target version

    my $v_found;
    my ($v0, $pvdata);
    while (($v0, $pvdata) = each %$vers) {
        do { $v_found++; last } if __match_v($target_ver, $v0);
    }
    unless ($v_found) {
        my $msg1 = join(
            "",
            "$pre: Target module '$target' version ($target_ver) is not ",
            "supported by patch module '$self', only these versions are ",
            "supported: ", join(" ", sort keys %$vers), ". ",
        );
        my $msg2 = join(
            "",
            "Not patching the module. If you insist on patching anyway, pass ",
            "the -on_unknown_version => 'force' option when 'use'-ing the ",
            "patch module."
        );
        my $msg3 = "Patching anyway.";
        if ($on_uv eq 'ignore') {
            # do not warn, but do nothing
            return;
        } elsif ($on_uv eq 'warn') {
            # warn, and do nothing
            carp $msg1 . $msg2;
            return;
        } elsif ($on_uv eq 'force') {
            # warn, and force patching
            carp $msg1 . $msg3;
        } else {
            # default is 'die'
            croak "FATAL: " . $msg1 . $msg2;
        }
    }

    # check conflict with other patch modules

    my @conflicts;
    $applied_patches{$target} //= [];
  CHECK_C:
    for my $pmod (@{$applied_patches{$target}}) {
        next if $pmod eq $self;

        my $opdata = $pmod->patch_data;
        my $overs = $opdata->{versions};
        my $opvdata;
        my $c;
        while (($v0, $opvdata) = each %$overs) {
            do { $c++; last } if __match_v($target_ver, $v0);
        }
        if ($c) {
            my $osubs = [keys %{$opvdata->{subs}}];
            for my $sub (keys %{$pvdata->{subs}}) {
                if ($sub ~~ @$osubs) {
                    push @conflicts, "$target\::$sub (from $pmod)";
                }
            }
        }
    }

    if (@conflicts) {
        my $msg1 = join(
            "",
            "$pre: Patch module '$self' conflicts with other loaded ",
            "patch modules, here are the conflicting subroutines: ",
            join(", ", @conflicts), ". "
        );
        my $msg2 = join(
            "",
            "Not patching the module. If you insist on patching anyway, pass ",
            "the -on_conflict => 'force' option when 'use'-ing the ",
            "patch module."
        );
        my $msg3 = "Patching anyway.";
        if ($on_c eq 'ignore') {
            # do not warn, but do nothing
            return;
        } elsif ($on_c eq 'warn') {
            carp $msg1 . $msg2;
            return;
        } elsif ($on_c eq 'force') {
            # warn, but apply anyway
            carp $msg1 . $msg3;
        } else {
            # default is 'die'
            croak "FATAL: " . $msg1 . $msg2;
        }
    }

    # patch!

    while (my ($n, $sub) = each %{$pvdata->{subs}}) {
        croak "FATAL: $pre: Target subroutine $target\::$n does not exist"
            unless defined(&{"$target\::$n"});

        $handle->{$n} = patch_package $target, $n, $sub;
    }
    push @{ $applied_patches{$target} }, $self;
}

sub unimport {
    no strict 'refs';

    my ($self) = @_;
    my $handle = \%{"$self\::handle"};

    delete $handle->{$_} for keys %$handle;
}

sub patch_data {
    die "BUG: patch_data() should be provided by subclass";
}

1;
# ABSTRACT: Base class for patch module

=head1 SYNOPSIS

 # in your patch module

 package Some::Module::patch::your_category;
 use parent qw(Module::Patch);

 sub patch_data {
     my $my_foo = sub {
         my $orig = shift;
         ...
     };
     return {
         versions => {
             # version specification can be a single version string
             '1.00' => {
                 subs => {
                     foo => $my_foo,
                     bar => sub { ... },
                     ...
                 },
             },

             # or multiple versions, separated by whitespace
             '1.02 1.03 /^2\..+$/' => {
                 ...
             },

             # also can contain a regex (/.../), no spaces in regex though. and
             # watch out for escapes.
             '1.99 /^2[.].+$/' => {
                 ...
             },
         },
     };
 }

 1;


 # using your patch module

 use Some::Module;
 use Some::Module::patch::your_category
     # optional, default is 'die'
     -on_unknown_version => 'warn',
     # optional, default is 'die'
     -on_conflict => 'warn'
 ;

 my $o = Some::Module->new;
 $o->foo(); # the patched version

 {
     no Some::Module::patch::your_category;
     $o->foo(); # the original version
 }


=head1 DESCRIPTION

Module::Patch helps you create a I<patch module>, a module that (monkey-)patches
other module by replacing some of its subroutines.

Patch module should be named I<Some::Module>::patch::I<your_category>. For
example, L<HTTP::Daemon::patch::ipv6>.

You specify patch information (which versions of target modules and which
subroutines to be replaced), while Module::Patch:

=over 4

=item * checks target module version

Can either die, display warning, or ignore if target module version is not
supported.

=item * checks other patch modules for the same target version

For example, if your patch module is C<Some::Module::patch::your_category>, it
will check other loaded C<Some::Module::patch::*> for conflicts, i.e. whether
the other patch modules want to patch the same subroutines. Can either die,
display warning, or ignore if there are conflicts.

=item * provides an import()/unimport() routine

unimport() will restore target module's original subroutines.

=back

=head2 Specifying patch information

Define patch_data() method. It should return a hash as shown in Synopsis.

Version can be a single version, or several versions separated by space.

=head2 Using the patch module

You simply 'use' the patch module. If the target module is not loaded, it will
be loaded by the patch module. The patch module will then wrap the target
subroutine(s) with the one(s) provided by the patch module. There are several
options available when importing:

=over 4

=item * -on_unknown_version => 'die'|'warn'|'ignore'|'force' (default: 'die')

If target module's version is not listed in the patch module, the default is to
die. 'warn' will display a warning and refuse to patch. 'ignore' will refuse to
patch without warning. 'force' will display warning and proceed with patching.

=item * -on_conflict => 'die'|'warn'|'ignore'|'force' (default: 'die')

If there is a conflict with other patch module(s), the default is to die. 'warn'
will display a warning and refuse to patch. 'ignore' will refuse to patch
without warning. 'force' will display warning and proceed with patching.

=item * -load_target => BOOL (default: 1)

Whether to attempt to load target module if it's not loaded. Normally you want
to keep this on, unless the target module is 'main' or already defined somewhere
else (not in the usual Module/SubModule.pm file expected by require()).

=back

If you are done and want to restore, unimport ('no' the patch module).


=head1 SEE ALSO

L<Pod::Weaver::Plugin::ModulePatch>

=cut
