#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 2;
use Test::Mojo;

use NCIPTest;

# From Koha
use C4::Context;
use Koha::Database;
use Koha::Libraries;
use Koha::Holds;
use Koha::Items;
use t::lib::Mocks;
use t::lib::TestBuilder;

my $schema = Koha::Database->schema;
$schema->storage->txn_begin;
my $builder = t::lib::TestBuilder->new;
my $dbh     = C4::Context->dbh;

# Start transaction
$dbh->{RaiseError} = 1;

my $plugin = NCIPTest::install_plugin();

my %koha_config = ();
NCIPTest::set_config( $plugin, { koha => \%koha_config } );

my $t = Test::Mojo->new('Koha::REST::V1');

my $dom;

my $patron_category = $builder->build(
    {
        source => 'Category',
        value  => {
            category_type                 => 'P',
            enrolmentfee                  => 0,
            BlockExpiredPatronOpacActions => -1,    # Pick the pref value
        }
    }
);

my $library = Koha::Libraries->search()->next();

my $patron_1 = $builder->build_object(
    {
        class => 'Koha::Patrons',
        value => {
            branchcode   => $library->id,
            categorycode => $patron_category->{categorycode},
            dateexpiry   => '2032-12-31',
        }
    }
);

my $item_1 = Koha::Items->search()->next();
$item_1->homebranch( $library->id );
$item_1->holdingbranch( $library->id );
$item_1->update();

my $module = new Test::MockModule('C4::Context');
$module->mock('userenv', sub { { branch => $library->id } });

subtest 'Test RequestItem with valid user and valid biblio' => sub {
    plan tests => 5;

    my $ncip_message = NCIPTest::render_fixture(
        'v1/RequestItem.xml',
        {
            user_identifier => $patron_1->cardnumber,
            biblionumber    => $item_1->biblionumber,
            branchcode      => $library->id,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    my $hold_id =
        $dom->{NCIPMessage}->{RequestItemResponse}->{UniqueRequestId}->{RequestIdentifierValue}->{text};
    ok( $hold_id, "RequestItemResponse returned a request id in the version 1 UniqueRequestId shape" );

    my $hold = Koha::Holds->find($hold_id);
    ok( $hold, "Request id is valid" );

    is( $hold->biblionumber, $item_1->biblionumber, "Hold is on the requested biblio" );
    is( $hold->borrowernumber, $patron_1->borrowernumber, "Hold is for the requesting patron" );
    is( $hold->itemnumber, undef, "Hold is record level" );
};

subtest 'Test that ItemRequested messages are not supported' => sub {
    plan tests => 2;

    # NCIP version 1 defines an ItemRequested message, which this server has
    # never implemented. The fixture was previously misnamed RequestItem.xml.
    my $ncip_message = NCIPTest::render_fixture('v1/ItemRequested.xml');

    my $tx = $t->ua->post( '/api/v1/contrib/ncip_server/ncip' => $ncip_message );
    is( $tx->res->code, 200, 'An ItemRequested message still gets a 200' );
    like( $tx->res->body, qr/It works!/, 'An ItemRequested message gets the fallback envelope' );
};

$schema->storage->txn_rollback;
