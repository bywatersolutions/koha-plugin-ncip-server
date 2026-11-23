#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 5;
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
    plan tests => 8;

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

    NCIPTest::set_config(
        $plugin,
        {
            allowed_ips => [ '216.147.212.121', '10.20.0.0/16', '2001:db8::/32' ],
            koha        => { userenv_borrowernumber => $patron->borrowernumber },
        }
    );
    is_deeply( $plugin->check_configuration, [], 'no errors for valid allowed_ips entries' );

    NCIPTest::set_config(
        $plugin,
        {
            allowed_ips => [ '216.147.212.121', '10.1.2.3/33', 'banana' ],
            koha        => { userenv_borrowernumber => $patron->borrowernumber },
        }
    );
    is_deeply(
        $plugin->check_configuration,
        [ { code => 'ALLOWED_IP_INVALID', ip => '10.1.2.3/33' }, { code => 'ALLOWED_IP_INVALID', ip => 'banana' } ],
        'ALLOWED_IP_INVALID for each allowed_ips entry that is not an address or range'
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

subtest 'check_configuration() schema validation tests' => sub {
    plan tests => 6;

    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my %valid_koha_config = ( userenv_borrowernumber => $patron->borrowernumber );

    # A misspelled key is flagged, misspelled keys otherwise silently do nothing
    NCIPTest::set_config(
        $plugin,
        { koha => { %valid_koha_config, lookup_userid => 'cardnumber' } }
    );
    my @schema_errors = grep { $_->{code} eq 'CONFIG_SCHEMA' } @{ $plugin->check_configuration };
    is( scalar @schema_errors, 1, 'A misspelled koha key gives one schema error' );
    like( $schema_errors[0]->{error}, qr/lookup_userid/, 'The schema error names the misspelled key' );

    # A value outside the enum is flagged
    NCIPTest::set_config(
        $plugin,
        { koha => { %valid_koha_config, lookup_user_id => 'carnumber' } }
    );
    @schema_errors = grep { $_->{code} eq 'CONFIG_SCHEMA' } @{ $plugin->check_configuration };
    is( scalar @schema_errors, 1, 'A bad lookup_user_id value gives one schema error' );
    like( $schema_errors[0]->{error}, qr{/koha/lookup_user_id}, 'The schema error points at lookup_user_id' );

    # A value of the wrong shape is flagged
    NCIPTest::set_config(
        $plugin,
        { koha => { %valid_koha_config, accept_item_uppercase_fields => 'biblio.title' } }
    );
    @schema_errors = grep { $_->{code} eq 'CONFIG_SCHEMA' } @{ $plugin->check_configuration };
    is( scalar @schema_errors, 1, 'A scalar accept_item_uppercase_fields gives one schema error' );

    # An unknown top level key is flagged, catches pasting a whole standalone config.yml
    NCIPTest::set_config(
        $plugin,
        { views => '/path/to/templates', koha => \%valid_koha_config }
    );
    @schema_errors = grep { $_->{code} eq 'CONFIG_SCHEMA' } @{ $plugin->check_configuration };
    is( scalar @schema_errors, 1, 'An unknown top level key gives one schema error' );
};

subtest 'is_ip_allowed() tests' => sub {
    plan tests => 11;

    NCIPTest::set_config( $plugin, { koha => {} } );
    $plugin->configuration( { force => 1 } );
    is( $plugin->is_ip_allowed('203.0.113.5'), 1, 'any address is allowed when allowed_ips is not set' );

    NCIPTest::set_config( $plugin, { allowed_ips => [], koha => {} } );
    $plugin->configuration( { force => 1 } );
    is( $plugin->is_ip_allowed('203.0.113.5'), 1, 'any address is allowed when allowed_ips is empty' );

    NCIPTest::set_config(
        $plugin,
        { allowed_ips => [ '216.147.212.121', '10.20.0.0/16', '2001:db8::/32' ], koha => {} }
    );
    $plugin->configuration( { force => 1 } );
    is( $plugin->is_ip_allowed('216.147.212.121'), 1, 'a listed address is allowed' );
    is( $plugin->is_ip_allowed('216.147.212.122'), 0, 'the address next to a listed one is refused' );
    is( $plugin->is_ip_allowed('10.20.5.5'),       1, 'an address inside a listed range is allowed' );
    is( $plugin->is_ip_allowed('10.21.0.1'),       0, 'an address outside a listed range is refused' );
    is( $plugin->is_ip_allowed('2001:db8::5'),     1, 'an IPv6 address inside a listed range is allowed' );
    is( $plugin->is_ip_allowed('2001:db9::5'),     0, 'an IPv6 address outside a listed range is refused' );

    NCIPTest::set_config( $plugin, { allowed_ips => '216.147.212.121', koha => {} } );
    $plugin->configuration( { force => 1 } );
    is( $plugin->is_ip_allowed('216.147.212.121'), 1, 'a single address given as a string is allowed' );
    is( $plugin->is_ip_allowed('203.0.113.5'),     0, 'other addresses are refused when allowed_ips is a string' );

    NCIPTest::set_config( $plugin, { allowed_ips => ['banana'], koha => {} } );
    $plugin->configuration( { force => 1 } );
    is( $plugin->is_ip_allowed('203.0.113.5'), 0, 'an entry that is not an address or range allows nothing' );
};

$schema->storage->txn_rollback;
