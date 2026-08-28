#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 4;
use Test::NoWarnings;

use NCIPTest;

# From Koha
use C4::Context;
use Koha::Database;

use Koha::Plugin::Com::ByWaterSolutions::NcipServer;

my $schema = Koha::Database->schema;
$schema->storage->txn_begin;
my $dbh = C4::Context->dbh;
$dbh->{RaiseError} = 1;

$dbh->do("DELETE FROM systempreferences WHERE variable IN ('NcipRequireToken','NcipToken')");

# Start from a clean slate even if the plugin is installed and configured on
# this Koha, we are in a transaction so this is rolled back
$dbh->do("DELETE FROM plugin_data WHERE plugin_class = 'Koha::Plugin::Com::ByWaterSolutions::NcipServer'");

my $plugin;

subtest 'install with no legacy sysprefs' => sub {
    plan tests => 1;

    # new() runs install() the first time the plugin is instantiated
    $plugin = Koha::Plugin::Com::ByWaterSolutions::NcipServer->new;

    is(
        $plugin->retrieve_data('configuration'),
        undef, 'no configuration is created when there is nothing to migrate'
    );
};

subtest 'install migrates the legacy sysprefs' => sub {
    plan tests => 4;

    $dbh->do("INSERT INTO systempreferences ( variable, value ) VALUES ('NcipRequireToken','1'),('NcipToken','sekrit')");

    $plugin->install;

    my ($count) =
        $dbh->selectrow_array("SELECT COUNT(*) FROM systempreferences WHERE variable IN ('NcipRequireToken','NcipToken')");
    is( $count, 0, 'the legacy sysprefs are deleted' );

    my $config = $plugin->configuration( { force => 1 } );
    is( $config->{token_required}, 1,        'token_required is copied from NcipRequireToken' );
    is( $config->{auth_token},     'sekrit', 'auth_token is copied from NcipToken' );

    is( $plugin->requires_token, 1, 'requires_token() is true after the migration' );
};

subtest 'install does not clobber existing configuration' => sub {
    plan tests => 3;

    $dbh->do("INSERT INTO systempreferences ( variable, value ) VALUES ('NcipRequireToken','0'),('NcipToken','other')");

    $plugin->install;

    my $config = $plugin->configuration( { force => 1 } );
    is( $config->{token_required}, 1,        'token_required keeps the previously migrated value' );
    is( $config->{auth_token},     'sekrit', 'auth_token keeps the previously migrated value' );

    my ($count) =
        $dbh->selectrow_array("SELECT COUNT(*) FROM systempreferences WHERE variable IN ('NcipRequireToken','NcipToken')");
    is( $count, 0, 'the legacy sysprefs are deleted anyway' );
};

$schema->storage->txn_rollback;
