#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib ( "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 4;    # last test to print

use_ok('Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::User');

ok( my $user = Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::User->new(), 'Create a new user object' );
ok( $user->userid('Chris'), 'Set userid' );
is( $user->userid(), 'Chris', "Test our getting" );
