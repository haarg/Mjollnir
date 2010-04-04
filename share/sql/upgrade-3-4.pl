use strict;
use warnings;
$::dbh->sqlite_create_function( 'filter_mw2_name', 1, sub {
    my $stripped_name = shift;
    $stripped_name =~ s/\^\d//g;
    return $stripped_name;
});
$::dbh->do('UPDATE player_names SET stripped_name = filter_mw2_name(name)');
