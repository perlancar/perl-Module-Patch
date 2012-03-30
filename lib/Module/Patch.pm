package Module::Patch;

use 5.010001;
use strict;
use warnings;

use Carp;
use Module::Loaded;
use Monkey::Patch qw(:all);

# VERSION

my %pkg; # key = caller

sub import {
    no strict 'refs';

    my ($self, %args) = @_;
    my $on_uv = $args{-on_unknown_version} // 'die';
    my $on_c  = $args{-on_conflict} // 'die';

    my $caller = caller();

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
    while (my ($v0, $pvdata) = each %$vers) {
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
            # do nothing, but do not patch
        } elsif ($on_uv eq 'warn') {
            carp $msg;
            return;
        } else {
            croak $msg;
        }
    }

    # check conflict with other patch modules

    my $prefix = "$target\::patch\::";
    my $sym = \%{$prefix};
    my ($conflict_pkg, $conflict_sub);
    for (grep {ref($sym->{$_}) eq 'HASH'} keys %$sym) {
        s/::$//;
        # XXX
    }
    if (defined $conflict_pkg) {
        my $msg = "Patch module '$self' conflicts with '$prefix$conflict_pkg'".
            ", both try to patch subroutine '$conflict_sub'";
        if ($on_c eq 'ignore') {
            # do nothing, apply anyway
        } elsif ($on_c eq 'warn') {
            carp $msg;
        } else {
            croak $msg;
        }
    }

    # call_package, put in $pkg{$caller}
}

sub unimport {
    my ($self) = @_;

    # restore by undef-ing $pkg{$caller}
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
 use Some::Module::patch::your_category;

 my $o = Some::Module->new;
 $o->foo(); # the patched version

 {
     no Some::Module::patch::your_category;
     $o->foo(); # the original version
 }


=head1 DESCRIPTION

Monkey::Patch helps you create a C<patch module>, a module that (monkey-)patches
other module by replacing some of its subroutines.

Patch module should be named I<Some::Module>::patch::I<your_category>. For
example, L<HTTP::Daemon::patch::ipv6>.

You specify patch information (which versions of target modules and which
subroutines to be replaced), while Monkey::Patch:

=over 4

=item * checks target module version

Will display warning (or croak) if target module version is not supported.

=item * checks other patch modules for the same target version

For example, if your patch module is C<Some::Module::patch::your_category>, it
will check other loaded C<Some::Module::patch::*> for conflicts, i.e. whether
the other patch modules want to patch the same subroutines.

=item * provides an import()/unimport() routine

unimport() will restore target module's original subroutines.

=back

=head2 Specifying patch information

Define patch_data() method. It should return a hash as shown in Synopsis.

Version can be a single version, or several versions separated by space.


=head1 SEE ALSO

L<Pod::Weaver::Plugin::ModulePatch>

=cut
