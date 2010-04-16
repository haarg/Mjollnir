use strict;
use warnings;

use Test::More;
use Test::MockObject;

use Mjollnir::IPBan ();

my $dispatch = Test::MockObject->new;
$dispatch->set_always(ban_ip => 'ban_ip return value');
$dispatch->set_always(clear_bans => 'clear_bans return value');
local $Mjollnir::IPBan::IMPL = $dispatch;

is Mjollnir::IPBan::ban_ip('127.0.0.1'), 'ban_ip return value', 'ban_ip returns correctly';
$dispatch->called_pos_ok(1, 'ban_ip');
$dispatch->called_args_pos_is(1, 2, '127.0.0.1');
$dispatch->clear;

is Mjollnir::IPBan::clear_bans(), 'clear_bans return value', 'clear_bans returns correctly';
$dispatch->called_pos_ok(1, 'clear_bans');
$dispatch->clear;

done_testing;
