package Module::Patch;

use 5.010001;
use strict;
use warnings;

use Carp;
use Module::Loaded;
use Monkey::Patch qw(:all);

# VERSION

sub import {
    no strict 'refs';

    my ($self, %args) = @_;
    my $handle = \%{"$self\::handle"};

    # already patched, ignore
    return if keys %$handle;

    my $on_uv = 'die';
    if ($args{-on_unknown_version}) {
        $on_uv = $args{-on_unknown_version};
        delete $args{-on_unknown_version};
    }
    my $on_c = 'die';
    if ($args{-on_conflict}) {
        $on_uv = $args{-on_conflict};
        delete $args{-on_conflict};
    }
    die "Unknown option: ".join(", ", keys %args) if %args;

    my $target = $self;
    $target =~ s/(?<=\w)::patch::\w+$//
        or croak "BUG: Bad patch module name '$target', it should end with ".
            "'::patch::something'";

    croak "$target is not loaded, please 'use $target' before patching"
        unless is_loaded($target);

    my $target_ver = ${"$target\::VERSION"};
    defined($target_ver) && length($target_ver)
        or croak "Target module '$target' does not have \$VERSION";

    my $pdata = $self->patch_data;
    ref($pdata) eq 'HASH'
        or die "BUG: patch_data() does not return a hash";
    my $vers = $pdata->{versions};
    ref($vers) eq 'HASH'
        or die "BUG: patch data must contain 'versions' and it must be a hash";

    # check target version

    my $v_found;
    my @all_v;
    my ($v0, $pvdata);
    while (($v0, $pvdata) = each %$vers) {
        my @v = split /[,;]?\s+/, $v0;
        push @all_v, @v;
        if ($target_ver ~~ @v) {
            $v_found++;
            last;
        }
    }
    unless ($v_found) {
        my $msg = "Target module '$target' version not supported by patch ".
            "module '$self', only these version(s) supported: ".
                join(" ", @all_v);
        if ($on_uv eq 'ignore') {
            # do not warn, but do nothing
            return;
        } elsif ($on_uv eq 'warn') {
            # warn, and do nothing
            carp $msg;
            return;
        } elsif ($on_uv eq 'force') {
            # warn, and force patching
            carp $msg;
        } else {
            # default is 'die'
            croak $msg;
        }
    }

    # check conflict with other patch modules

    my $prefix = "$target\::patch\::";
    my $sym = \%{$prefix};
    my @conflicts;
  CHECK_C:
    for my $n (grep {ref($sym->{$_}) eq 'HASH'} keys %$sym) {
        $n =~ s/::$//;
        my $fn = "$prefix\::$n";
        my $fnp = $fn; $fnp =~ s!::!/!g; $fnp .= ".pm";
        eval { require $fnp };
        die "Can't load '$fn' when checking for conflict: $@" if $@;

        my $opdata = $fnp->patch_data;
        my $overs = $opdata->{versions};
        my $opvdata;
        my $c;
        while (($v0, $opvdata) = each %$overs) {
            my @v = split /[,;]?\s+/, $v0;
            if ($target_ver ~~ @v) {
                $c++;
                last;
            }
        }
        if ($c) {
            my $osubs = keys %{$opvdata->{subs}};
            for my $sub (keys %{$pvdata->{subs}}) {
                if ($sub ~~ @$osubs) {
                    push @conflicts, "$target\::$sub (from $fn)";
                }
            }
        }
    }

    if (@conflicts) {
        my $msg = "Patch module '$self' conflicts with other loaded ".
            "patch modules, here are the conflicting subroutines: ".
                join(", ", @conflicts);
        if ($on_c eq 'ignore') {
            # do not warn, but do nothing
            return;
        } elsif ($on_c eq 'warn') {
            carp $msg;
            return;
        } elsif ($on_c eq 'force') {
            # warn, but apply anyway
            carp $msg;
        } else {
            # default is 'die'
            croak $msg;
        }
    }

    # patch!

    while (my ($n, $sub) = each %{$pvdata->{subs}}) {
        $handle->{$n} = patch_package $target, $n, $sub;
    }

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
     my $foo = sub {
         my $orig = shift;
         ...
     };
     return {
         versions => {
             '1.00' => {
                 subs => {
                     foo => $my_foo,
                 },
             },
             '1.02 1.03' => {
                 subs => {
                     foo => $my_foo,
                 },
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

Module::Patch helps you create a C<patch module>, a module that (monkey-)patches
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

First 'use' the target module. Patch module will refuse to load unless target
module is already loaded.

Then 'use' the patch module. This will wrap the target subroutine(s) with the
one(s) provided by the patch module. There are several options available when
importing:

=over 4

=item * -on_unknown_version => 'die'|'warn'|'ignore'|'force' (default: 'die')

If target module's version is not listed in the patch module, the default is to
die. 'warn' will display a warning and refuse to patch. 'ignore' will refuse to
patch without warning. 'force' will display warning and proceed with patching.

=item * -on_conflict => 'die'|'warn'|'ignore'|'force' (default: 'die')

If there is a conflict with other patch module(s), the default is to die. 'warn'
will display a warning and refuse to patch. 'ignore' will refuse to patch
without warning. 'force' will display warning and proceed with patching.

=back

If you are done and want to restore, unimport ('no' the patch module).


=head1 SEE ALSO

L<Pod::Weaver::Plugin::ModulePatch>

=cut
