package Mjollnir::IPBan;
use strict;
use warnings;

our $IMPL;
BEGIN {
    if (! $IMPL) {
        if ($ENV{MJOL_DEBUG}) {
            $IMPL = 'Mjollnir::IPBan::Debug';
        }
        elsif ($^O eq 'MSWin32') {
            require Win32;
            my (undef, $major, $minor, $build) = Win32::GetOSVersion();
            my $version = sprintf '%d.%03d', $major, $minor;
            if ($version == 5.001) {
                $IMPL = 'Mjollnir::IPBan::ipseccmd';
            }
            elsif ($version > 5.001) {
                $IMPL = 'Mjollnir::IPBan::netsh';
            }
        }
    }
    if ($IMPL) {
        eval "require $IMPL"
            or die $@;
    }
    else {
        die "Unable to find implementation for IP bans.\n";
    }
}

sub ban_ip {
    $IMPL->ban_ip(@_);
}

sub clear_bans {
    $IMPL->clear_bans(@_);
}

1;

__END__

=head1 NAME

Mjollnir::IPBan - IP banning for Mjollnir

=head1 METHODS

=head2 ban_ip ( $ip )

=head2 clear_bans ( )

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
