package Module::Patch;

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use Carp;
use Module::Load;
use Module::Loaded;
use Monkey::Patch qw();
use Scalar::Util qw(reftype);
use SHARYANTO::Array::Util qw(match_array_or_regex);
use SHARYANTO::Package::Util qw(list_package_contents package_exists);

# VERSION

our @EXPORT_OK = qw(patch_package);

#our %applied_patches; # for conflict checking

sub import {
    no strict 'refs';
    no warnings; # W lines generate warnings

    my $self = shift;

    if ($self eq __PACKAGE__) {
        # we are not subclassed, provide exports
        my @caller = caller;
        for (@_) {
            croak "$_ is not exported by ".__PACKAGE__ unless $_ ~~ @EXPORT_OK;
            *{"$caller[0]::$_"} = \&$_;
        }
    } else {
        # we are subclassed, patch caller with patch_data()
        my %opts = @_;

        my $load;
        if (exists $opts{-load_target}) {
            $load = $opts{-load_target};
            delete $opts{-load_target};
        }
        $load //= 1;
        my $force;
        if (exists $opts{-force}) {
            $force = $opts{-force};
            delete $opts{-force};
        }
        $force //= 0;

        # patch already applied, ignore
        return if ${"$self\::handles"}; #W

        my $pdata = $self->patch_data or
            die "BUG: $self: No patch data supplied";
        if (($pdata->{v} // 1) < 2) {
            croak "$self requires Module::Patch 0.06 or earlier ".
                "(old patch_data format), please install Module::Patch 0.06 ".
                    "or upgrade $self to use new patch_data format";
        }

        my $target = $self;
        $target =~ s/(?<=\w)::patch::\w+$//
            or die "BUG: $self: Bad patch module name '$target', it should ".
                "end with '::patch::something'";

        unless (is_loaded($target)) {
            if ($load) {
                load $target;
            } else {
                croak "FATAL: $self: $target is not loaded, please ".
                    "'use $target' before patching";
            }
        }

        # read patch module's configs
        my $pcdata = $pdata->{config} // {};
        my $config = \%{"$self\::config"};
        while (my ($k, $v) = each %$pcdata) {
            $config->{$k} = $v->{default};
            if (exists $opts{$k}) {
                $config->{$k} = $opts{$k};
                delete $opts{$k};
            }
        }

        if (keys %opts) {
            croak "$self: Unknown option(s): ".join(", ", keys %opts);
        }

        ${"$self\::handles"} = patch_package(
            $target, $pdata->{patches}, {force=>$force});
    }
}

sub unimport {
    no strict 'refs';

    my $self = shift;

    if ($self eq __PACKAGE__) {
        # do nothing
    } else {
        my $handles = ${"$self\::handles"};
        $log->tracef("Unpatching %s ...", [keys %$handles]);
        undef ${"$self\::handles"};
        # do we need to undef ${"$self\::config"}?, i'm thinking not really
    }
}

sub patch_data {
    die "BUG: patch_data() should be provided by subclass";
}

sub patch_package {
    no strict 'refs';

    my ($package0, $patches_spec, $opts) = @_;
    $opts //= {};

    my $handles = {};
    for my $target (ref($package0) eq 'ARRAY' ? @$package0 : ($package0)) {
        croak "FATAL: Target module '$target' not loaded"
            unless package_exists($target);
        my $target_version = ${"$target\::VERSION"};
        my @target_subs;
        my %tp = list_package_contents($target);
        for (keys %tp) {
            if (reftype($tp{$_}) eq 'CODE' && !/^\*/) { push @target_subs, $_ }
        }

        my $i = 0;
      PATCH:
        for my $pspec (@$patches_spec) {
            $pspec->{action} or die "BUG: patch[$i]: no action supplied";
            $pspec->{action} eq 'wrap' or die "BUG: patch[$i]: ".
                "action '$pspec->{action}' unknown/unimplemented";
            $pspec->{code} or die "BUG: patch[$i]: no code supplied";

            my $sub_names = ref($pspec->{sub_name}) eq 'ARRAY' ?
                [@{ $pspec->{sub_name} }] : [$pspec->{sub_name}];
            for (@$sub_names) {
                $_ = qr/.*/    if $_ eq ':all';
                $_ = qr/^_/    if $_ eq ':private';
                $_ = qr/^[^_]/ if $_ eq ':public';
                die "BUG: patch[$i]: unknown tag in sub_name $_" if /^:/;
            }

            my @s;
            for my $sub_name (@$sub_names) {
                if (ref($sub_name) eq 'Regexp') {
                    for (@target_subs) {
                        push @s, $_ if $_ !~~ @s && $_ =~ $sub_name;
                    }
                } elsif ($sub_name ~~ @target_subs) {
                    push @s, $sub_name;
                } else {
                    die "BUG: patch[$i]: no subroutine named $sub_name ".
                        "found in target package $target";
                }
            }

            unless (!defined($pspec->{mod_version}) ||
                        $pspec->{mod_version} eq ':all') {
                defined($target_version) && length($target_version)
                    or croak "FATAL: Target package '$target' does not have ".
                        "\$VERSION";
                my $mod_versions = $pspec->{mod_version};
                $mod_versions = ref($mod_versions) eq 'ARRAY' ?
                    [@$mod_versions] : [$mod_versions];
                for (@$mod_versions) {
                    $_ = qr/.*/    if $_ eq ':all';
                    die "BUG: patch[$i]: unknown tag in mod_version $_"
                        if /^:/;
                }

                my $ver_match=match_array_or_regex(
                    $target_version, $mod_versions);
                unless ($ver_match) {
                    carp "patch[$i]: Target module version $target_version ".
                        "does not match [".join(", ", @$mod_versions)."], ".
                            ($opts->{force} ?
                                 "patching anyway (force)":"skipped"). ".";
                    next PATCH unless $opts->{force};
                }
            }

            for my $s (@s) {
                $log->tracef("Patching %s ...", $s);
                my $ctx = {
                    orig_name => "$target\::$s",
                };
                $handles->{"$target\::$s"} = Monkey::Patch::patch_package(
                    $target, $s,
                    sub { unshift @_, $ctx; goto &{$pspec->{code}} }
                );
            }

            $i++;
        } # for $pspec
    } # for $target
    $handles;
}

1;
# ABSTRACT: Patch package with a set of patches

=head1 SYNOPSIS

To use Module::Patch directly:

 # patching DBI modules so that

 use Module::Patch qw(patch_package);
 use Log::Any '$log';
 patch_package(['DBI', 'DBI::st', 'DBI::db'], [
     {action=>'wrap', mod_version=>':all', sub_name=>':public', code=>sub {
         my $ctx      = shift;
         my $orig_sub = shift;
         $log->tracef("Entering %s(%s) ...", $ctx->{orig_name}, \@_);
         my $res;
         if (wantarray) { $res=[$orig_sub->(@_)] } else { $res=$orig_sub->(@_) }
         $log->tracef("Returned from %s", $ctx->{orig_name});
         if (wantarray) { return @$res } else { return $res }
     }},
 ]);

To create a patch module by subclassing Module::Patch:

 # in your patch module

 package Some::Module::patch::your_category;
 use parent qw(Module::Patch);

 sub patch_data {
     return {
         v => 2,
         patches => [...], # $patches_spec
         config => { # per-patch-module config
             a => {
                 default => 1,
             },
             b => {},
             c => {
                 default => 3,
             },
         },
     };
 }
 1;

 # using your patch module

 use Some::Module::patch::your_category
     -force => 1, # optional, force patch even if target version does not match
     -config => {a=>10, b=>20}, # optional, set config value
 ;

 # accessing per-patch-module config data

 print $Some::Module::patch::your_category::config->{a}; # 10
 print $Some::Module::patch::your_category::config->{c}; # 3, default value

 # unpatch, restore original subroutines
 no Some::Module::patch::your_category;


=head1 DESCRIPTION

Module::Patch is basically a convenient way to define and bundle a set of
patches. Actual patching is done by the nice L<Monkey::Patch>, which provides
lexically scoped patching.

There are two ways to use this module:

=over 4

=item * subclass it

This is used for convenient bundling of patches. You create a I<patch module> (a
module that monkey-patches other module by adding/wrapping/deleting subroutines
of target module) by subclassing Module::Patch and providing the patches_spec in
patch_data() method.

Patch module should be named I<Some::Module>::patch::I<your_category>. For
example, L<HTTP::Daemon::patch::ipv6>.

=item * require/import it directly

Module::Patch provides B<patch_package> which is the actual routine to do the
patching.

=back


=head1 FUNCTIONS

=head2 import()

If imported directly, will export @exports as arguments and export requested
symbols.

If imported from subclass, will take %opts as arguments and run patch_package()
on caller package. %opts include:

=over 4

=item * -load_target => BOOL (default 1)

Load target modules. Set to 0 if package is already defined in other files and
cannot be require()-ed.

=item * -force => BOOL

Will be passed to patch_package's \%opts.

=back

=head2 patch_package($package, $patches_spec, \%opts)

Patch target package C<$package> with a set of patches.

C<$patches_spec> is an arrayref containing a series of patch specification.
Patch specification is a hashref containing these keys: C<action> (string,
required; either 'wrap', 'add', 'delete'), C<mod_version> (string/regex or array
of string/regex, can be ':all' to mean all versions; optional; defaults to
':all'). C<sub_name> (string/regex or array of string/regex, subroutine(s) to
patch, can be ':all' to mean all subroutine, ':public' to mean all public
subroutines [those not prefixed by C<_>], ':private' to mean all private),
C<code> (coderef, not required if C<action> is 'delete').

Die if there is conflict when patching, for example if target module has been
patched 'delete' and another patch wants to 'wrap' it.

NOTE: Action 'add', 'delete', and conflict checking not yet implemented.

Known options:

=over 4

=item * force => BOOL (default 0)

Force patching even if target module version does not match. The default is to
warn and skip patching.

=back


=head1 SEE ALSO

L<Monkey::Patch>

L<Pod::Weaver::Plugin::ModulePatch>

Some examples of patch modules that use Module::Patch by subclassing it:
L<Net::HTTP::Methods::patch::log_request>,
L<LWP::UserAgent::patch::https_hard_timeout>.

Some examples of modules that use Module::Patch directly:
L<Log::Any::For::Class>.

=cut
