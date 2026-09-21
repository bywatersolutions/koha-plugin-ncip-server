#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 8;
use Test::NoWarnings;
use Test::Warn;
use Test::Mojo;

use NCIPTest;

# From Koha
use Koha::Database;

my $schema = Koha::Database->schema;
$schema->storage->txn_begin;

my $plugin = NCIPTest::install_plugin();
NCIPTest::set_config( $plugin, { koha => {} } );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'token not required' => sub {
    plan tests => 5;

    my $tx = $t->ua->post('/api/v1/contrib/ncip_server/ncip');
    is( $tx->res->code, 200, 'POST without a token gets a 200' );
    like( $tx->res->body, qr/It works!/, 'POST without a token gets the NCIP envelope' );

    $tx = $t->ua->get('/api/v1/contrib/ncip_server/ncip');
    is( $tx->res->code, 200, 'GET without a token gets a 200' );
    like( $tx->res->body, qr/It works!/, 'GET without a token gets the NCIP envelope' );

    $tx = $t->ua->post('/api/v1/contrib/ncip_server/ncip/anytoken');
    is( $tx->res->code, 403, 'POST with a token gets a 403 when no token is configured' );
};

subtest 'token configured but not required' => sub {
    plan tests => 3;

    NCIPTest::set_config( $plugin, { auth_token => 'sekrit', koha => {} } );

    my $tx = $t->ua->post('/api/v1/contrib/ncip_server/ncip');
    is( $tx->res->code, 200, 'POST without a token gets a 200' );

    $tx = $t->ua->post('/api/v1/contrib/ncip_server/ncip/wrongtoken');
    is( $tx->res->code, 403, 'POST with the wrong token gets a 403' );

    $tx = $t->ua->post('/api/v1/contrib/ncip_server/ncip/sekrit');
    is( $tx->res->code, 200, 'POST with the correct token gets a 200' );
};

subtest 'token required' => sub {
    plan tests => 7;

    NCIPTest::set_config( $plugin, { token_required => 1, auth_token => 'sekrit', koha => {} } );

    my $tx = $t->ua->post('/api/v1/contrib/ncip_server/ncip');
    is( $tx->res->code, 403, 'POST without a token gets a 403' );
    is(
        $tx->res->json->{error},
        'Invalid or missing authorization token',
        'POST without a token gets the token error'
    );

    $tx = $t->ua->get('/api/v1/contrib/ncip_server/ncip');
    is( $tx->res->code, 403, 'GET without a token gets a 403' );

    $tx = $t->ua->post('/api/v1/contrib/ncip_server/ncip/wrongtoken');
    is( $tx->res->code, 403, 'POST with the wrong token gets a 403' );

    $tx = $t->ua->post('/api/v1/contrib/ncip_server/ncip/sekrit');
    is( $tx->res->code, 200, 'POST with the correct token gets a 200' );
    like( $tx->res->body, qr/It works!/, 'POST with the correct token gets the NCIP envelope' );

    $tx = $t->ua->get('/api/v1/contrib/ncip_server/ncip/sekrit');
    is( $tx->res->code, 200, 'GET with the correct token gets a 200' );
};

subtest 'invalid configuration' => sub {
    plan tests => 3;

    $plugin->store_data( { configuration => "foo: [unclosed" } );

    my $tx;
    warning_like { $tx = $t->ua->post('/api/v1/contrib/ncip_server/ncip') } qr/NCIP CONFIG ERROR/,
        'a stored configuration that is not valid YAML warns';
    is( $tx->res->code, 500, 'a broken configuration gets a 500 instead of failing open' );
    is(
        $tx->res->json->{error},
        'NCIP server plugin configuration is invalid',
        'a broken configuration gets the configuration error'
    );

    NCIPTest::set_config( $plugin, { koha => {} } );
};

subtest 'request body converted to JSON by Koha ( Bug 37762 )' => sub {
    plan tests => 2;

    # On Koha 26.05 and later an application/xml request body reaches the
    # controller converted to JSON. The controller can't recover the message,
    # but it should still answer with the NCIP envelope, not an error.
    my $tx = $t->ua->post(
        '/api/v1/contrib/ncip_server/ncip' => { 'Content-Type' => 'application/xml' } => '{"NCIPMessage":{}}' );
    is( $tx->res->code, 200, 'a JSON body sent as application/xml still gets a 200' );
    like( $tx->res->body, qr/It works!/, 'a JSON body sent as application/xml gets the NCIP envelope' );
};

subtest 'NCIP message sent with an application/xml content type' => sub {
    plan tests => 3;

    # This must work on every Koha. Before 26.05 the body arrives untouched.
    # On 26.05 and later ( Bug 37762 ) Koha converts the body to JSON before
    # the controller runs, and the controller recovers it, from the buffered
    # PSGI input in a real deployment, or by rebuilding the XML from the JSON
    # conversion when there is no PSGI environment ( as here, in-process )
    my $lookupversion = NCIPTest::render_fixture('v2/LookupVersion.xml');

    my $tx = $t->ua->post(
        '/api/v1/contrib/ncip_server/ncip' => { 'Content-Type' => 'application/xml' } => $lookupversion );
    is( $tx->res->code, 200, 'NCIP posted as application/xml gets a 200' );
    like(
        $tx->res->body, qr/LookupVersionResponse/,
        'NCIP posted as application/xml gets a real response, not the fallback envelope'
    );
    like( $tx->res->body, qr/VersionSupported/, 'The response lists the supported versions' );
};

subtest 'unsupported message type' => sub {
    plan tests => 2;

    # There is no CreateUser handler, so the Handler whitelist dies and the
    # controller answers with the "It works!" envelope instead
    my $createuser = NCIPTest::render_fixture('v2/CreateUser.xml');

    my $tx = $t->ua->post( '/api/v1/contrib/ncip_server/ncip' => $createuser );
    is( $tx->res->code, 200, 'an unsupported message type still gets a 200' );
    like( $tx->res->body, qr/It works!/, 'an unsupported message type gets the NCIP envelope' );
};

$schema->storage->txn_rollback;
