package Mjollnir::IPBan;
use strict;
use warnings;

BEGIN {
    if ($^O eq 'MSWin32') {
        require Win32;
        my (undef, $major, $minor, $build) = Win32::GetOSVersion();
        my $version = sprintf '%d.%03d', $major, $minor;
        if ($version == 5.001) {
            require Mjollnir::IPBan::ipseccmd;
            Mjollnir::IPBan::ipseccmd->import;
            return;
        }
        elsif ($version > 5.001) {
            require Mjollnir::IPBan::netsh;
            Mjollnir::IPBan::netsh->import;
            return;
        }
    }
    die "Unable to find implementation for IP bans.\n";
}

1;

__END__

=head1 NAME

Mjollnir::IPBan - IP banning for Mjollnir

=head1 SUBROUTINES

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
