#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 3;
use Test::NoWarnings;
use Test::Warn;

use NCIPTest;

# From Koha
use C4::Context;
use Koha::Database;
use t::lib::TestBuilder;

use Koha::Plugin::Com::ByWaterSolutions::NcipServer;

my $schema = Koha::Database->schema;
$schema->storage->txn_begin;
my $builder = t::lib::TestBuilder->new;

# Start from a clean slate even if the plugin is installed and configured on
# this Koha, we are in a transaction so this is rolled back
C4::Context->dbh->do("DELETE FROM plugin_data WHERE plugin_class = 'Koha::Plugin::Com::ByWaterSolutions::NcipServer'");

my $plugin = Koha::Plugin::Com::ByWaterSolutions::NcipServer->new;

subtest 'configuration() tests' => sub {
    plan tests => 5;

    is_deeply( $plugin->configuration( { force => 1 } ), {}, 'no stored configuration deserializes to an empty hash' );

    NCIPTest::set_config( $plugin, { auth_token => 'sekrit', koha => { framework => 'FA' } } );
    my $config = $plugin->configuration( { force => 1 } );
    is( $config->{auth_token},        'sekrit', 'top level keys are deserialized' );
    is( $config->{koha}->{framework}, 'FA',     'the koha block is deserialized' );

    $plugin->store_data( { configuration => "foo: [unclosed" } );
    my $broken;
    warning_like { $broken = $plugin->configuration( { force => 1 } ) } qr/NCIP CONFIG ERROR/,
        'a configuration that is not valid YAML warns';
    is( $broken, undef, 'a configuration that is not valid YAML returns undef' );
};

subtest 'check_configuration() tests' => sub {
    plan tests => 6;

    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );

    NCIPTest::set_config( $plugin, { koha => { userenv_borrowernumber => $patron->borrowernumber } } );
    is_deeply( $plugin->check_configuration, [], 'no errors for a valid configuration' );

    NCIPTest::set_config(
        $plugin,
        {
            token_required => 1,
            koha           => { userenv_borrowernumber => $patron->borrowernumber },
        }
    );
    is_deeply(
        $plugin->check_configuration,
        [ { code => 'AUTH_TOKEN_MISSING' } ],
        'AUTH_TOKEN_MISSING when token_required is set without an auth_token'
    );

    NCIPTest::set_config( $plugin, { koha => {} } );
    is_deeply(
        $plugin->check_configuration,
        [ { code => 'USERENV_NOT_SET' } ],
        'USERENV_NOT_SET when there is no userenv_borrowernumber'
    );

    my $deleted_patron    = $builder->build_object( { class => 'Koha::Patrons' } );
    my $deleted_patron_id = $deleted_patron->borrowernumber;
    $deleted_patron->delete;
    NCIPTest::set_config( $plugin, { koha => { userenv_borrowernumber => $deleted_patron_id } } );
    is_deeply(
        $plugin->check_configuration,
        [ { code => 'USERENV_NOT_FOUND', borrowernumber => $deleted_patron_id } ],
        'USERENV_NOT_FOUND when userenv_borrowernumber is not a real patron'
    );

    $plugin->store_data( { configuration => "foo: [unclosed" } );
    my $errors;
    warning_like { $errors = $plugin->check_configuration } qr/NCIP CONFIG ERROR/,
        'a configuration that is not valid YAML warns';
    is_deeply(
        $errors,
        [ { code => 'CONFIGURATION_INVALID' } ],
        'CONFIGURATION_INVALID when the configuration is not valid YAML'
    );
};

$schema->storage->txn_rollback;
