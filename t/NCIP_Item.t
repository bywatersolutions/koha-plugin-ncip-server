#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib ( "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 3;    # last test to print

use_ok('Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Item');

ok( my $user = Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Item->new( { itemid => 1 } ), 'Create a new item object' );
is( $user->itemid(), '1', "Test getting itemid" );
