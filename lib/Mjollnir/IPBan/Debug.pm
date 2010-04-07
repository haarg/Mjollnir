package Mjollnir::IPBan::Debug;
use strict;
use warnings;

our $VERSION = 0.01;

sub ban_ip {
    my $class = shift;
    my $ip = shift;
    warn "Banning IP $ip.\n";
    return 1;
}

sub clear_bans {
    warn "Clearing IP bans.\n";
    return 1;
}

1;

__END__

=head1 NAME

Mjollnir::IPBan::Debug - Fake IP banning controls

=head1 AUTHOR

Graham Knop <haarg@haarg.org>

=head1 LICENSE

Copyright (c) 2010, Graham Knop

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0. For more details, see the
full text of the licenses in the directory LICENSES.

=cut
