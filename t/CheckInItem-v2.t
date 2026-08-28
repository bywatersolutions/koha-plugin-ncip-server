#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 7;
use Test::Mojo;

use NCIPTest;

# From Koha
use C4::Circulation;
use C4::Reserves;
use Koha::Database;
use Koha::Holds;
use Koha::Items;
use Koha::Libraries;
use Koha::Patrons;
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

my $library   = Koha::Libraries->search()->next();
my $library_2 = $builder->build_object( { class => 'Koha::Libraries' } );

my $patron_1 = $builder->build_object(
    {
        class => 'Koha::Patrons',
        value => {
            branchcode   => $library->id,
            categorycode => $patron_category->{categorycode},
            dateexpiry   => '2032-12-31',
            firstname    => 'Kyle',
            surname      => 'Hall',
            userid       => 'khall',
        }
    }
);

my $item_1 = Koha::Items->search()->next();
$item_1->homebranch( $library->id );
$item_1->holdingbranch( $library->id );
$item_1->update();
#
# Need to mock userenv for AddIssue
my $module = new Test::MockModule('C4::Context');
$module->mock('userenv', sub { { branch => $library->id } });

subtest 'Test CheckInItem with valid user and item' => sub {
    plan tests => 1;

    $koha_config{no_error_on_return_without_checkout} = 1;
    $koha_config{trap_hold_on_checkin} = 0;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $issue = C4::Circulation::AddIssue( $patron_1, $item_1->barcode );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/CheckInItem.xml',
        {
            item_identifier => $item_1->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $item_1->barcode,
        'CheckInItemResponse returns correct item barcode for item checked out by patron'
    );

    $issue->delete(); # Just in case checkin fails
};

subtest 'Test CheckInItem without checkout' => sub {
    plan tests => 5;

    $koha_config{no_error_on_return_without_checkout} = 1;
    $koha_config{trap_hold_on_checkin} = 0;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/CheckInItem.xml',
        {
            item_identifier => $item_1->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $item_1->barcode,
        'CheckInItemResponse returns correct item barcode for item not checked out by a patron, no_error_on_return_without_checkout = 1'
    );

    $koha_config{no_error_on_return_without_checkout} = 0;
    $koha_config{trap_hold_on_checkin} = 0;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{Problem}->{ProblemElement}->{text},
        'UniqueItemIdentifier',
        'CheckInItemResponse returns correct problem element for item not checked out by a patron, no_error_on_return_without_checkout = 0, trap_hold_on_checkin = 0'
    );
    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{Problem}->{ProblemDetail}->{text},
        'There is no record of the check out of the item.',
        'CheckInItemResponse returns correct problem detail for item not checked out by a patron, no_error_on_return_without_checkout = 0, trap_hold_on_checkin = 0'
    );
    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{Problem}->{ProblemType}->{text},
        'Item Not Checked Out',
        'CheckInItemResponse returns correct problem type for item not checked out by a patron, no_error_on_return_without_checkout = 0, trap_hold_on_checkin = 0'
    );
    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{Problem}->{ProblemValue}->{text},
        $item_1->barcode,
        'CheckInItemResponse returns correct problem value for item not checked out by a patron, no_error_on_return_without_checkout = 0, trap_hold_on_checkin = 0'
    );
};

subtest 'Test CheckInItem with delete_item_on_checkin' => sub {
    plan tests => 2;

    $koha_config{no_error_on_return_without_checkout}  = 0;
    $koha_config{trap_hold_on_checkin}                 = 0;
    $koha_config{delete_item_on_checkin}               = 1;
    $koha_config{delete_item_on_checkin_itemtype}      = 0;
    $koha_config{delete_item_on_checkin_homebranch}    = 0;
    $koha_config{delete_item_on_checkin_holdingbranch} = 0;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $item = $builder->build_sample_item( { library => $library->id } );

    C4::Circulation::AddIssue( $patron_1, $item->barcode );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/CheckInItem.xml',
        {
            item_identifier => $item->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $item->barcode,
        'CheckInItemResponse returns correct item barcode with delete_item_on_checkin = 1'
    );
    is(
        Koha::Items->find( $item->id ),
        undef,
        'Item has been deleted after checkin'
    );
};

subtest 'Test CheckInItem with delete_item_on_checkin_itemtype' => sub {
    plan tests => 4;

    $koha_config{no_error_on_return_without_checkout}  = 0;
    $koha_config{trap_hold_on_checkin}                 = 0;
    $koha_config{delete_item_on_checkin}               = 1;
    $koha_config{delete_item_on_checkin_homebranch}    = 0;
    $koha_config{delete_item_on_checkin_holdingbranch} = 0;

    my $item = $builder->build_sample_item( { library => $library->id } );

    $koha_config{delete_item_on_checkin_itemtype} = $item->effective_itemtype;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    C4::Circulation::AddIssue( $patron_1, $item->barcode );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/CheckInItem.xml',
        {
            item_identifier => $item->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $item->barcode,
        'CheckInItemResponse returns correct item barcode for item with matching itemtype'
    );
    is(
        Koha::Items->find( $item->id ),
        undef,
        'Item with matching itemtype has been deleted after checkin'
    );

    # A second sample item gets its own new itemtype, so it cannot match the limit above
    my $item_2 = $builder->build_sample_item( { library => $library->id } );

    C4::Circulation::AddIssue( $patron_1, $item_2->barcode );

    $ncip_message = NCIPTest::render_fixture(
        'v2/CheckInItem.xml',
        {
            item_identifier => $item_2->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $item_2->barcode,
        'CheckInItemResponse returns correct item barcode for item with non-matching itemtype'
    );
    ok(
        Koha::Items->find( $item_2->id ),
        'Item with non-matching itemtype has not been deleted after checkin'
    );
};

subtest 'Test CheckInItem with delete_item_on_checkin_homebranch' => sub {
    plan tests => 2;

    $koha_config{no_error_on_return_without_checkout}  = 0;
    $koha_config{trap_hold_on_checkin}                 = 0;
    $koha_config{delete_item_on_checkin}               = 1;
    $koha_config{delete_item_on_checkin_itemtype}      = 0;
    $koha_config{delete_item_on_checkin_homebranch}    = $library_2->branchcode;
    $koha_config{delete_item_on_checkin_holdingbranch} = 0;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $item = $builder->build_sample_item( { library => $library->id } );

    C4::Circulation::AddIssue( $patron_1, $item->barcode );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/CheckInItem.xml',
        {
            item_identifier => $item->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $item->barcode,
        'CheckInItemResponse returns correct item barcode for item with non-matching homebranch'
    );
    ok(
        Koha::Items->find( $item->id ),
        'Item with non-matching homebranch has not been deleted after checkin'
    );
};

subtest 'Test CheckInItem with delete_item_on_checkin_holdingbranch' => sub {
    plan tests => 2;

    $koha_config{no_error_on_return_without_checkout}  = 0;
    $koha_config{trap_hold_on_checkin}                 = 0;
    $koha_config{delete_item_on_checkin}               = 1;
    $koha_config{delete_item_on_checkin_itemtype}      = 0;
    $koha_config{delete_item_on_checkin_homebranch}    = 0;
    $koha_config{delete_item_on_checkin_holdingbranch} = $library_2->branchcode;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $item = $builder->build_sample_item( { library => $library->id } );

    C4::Circulation::AddIssue( $patron_1, $item->barcode );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/CheckInItem.xml',
        {
            item_identifier => $item->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $item->barcode,
        'CheckInItemResponse returns correct item barcode for item with non-matching holdingbranch'
    );
    ok(
        Koha::Items->find( $item->id ),
        'Item with non-matching holdingbranch has not been deleted after checkin'
    );
};

subtest 'Test CheckInItem with trap_hold_on_checkin' => sub {
    plan tests => 6;

    $koha_config{no_error_on_return_without_checkout}  = 0;
    $koha_config{trap_hold_on_checkin}                 = 1;
    $koha_config{delete_item_on_checkin}               = 0;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $patron_2 = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => {
                branchcode   => $library->id,
                categorycode => $patron_category->{categorycode},
                dateexpiry   => '2032-12-31',
            }
        }
    );

    # A hold with pickup at the item's holding branch is trapped as waiting
    my $item = $builder->build_sample_item( { library => $library->id } );

    my $reserve_id = C4::Reserves::AddReserve(
        {
            branchcode     => $library->id,
            borrowernumber => $patron_2->id,
            biblionumber   => $item->biblionumber,
            itemnumber     => $item->id,
            priority       => 1,
        }
    );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/CheckInItem.xml',
        {
            item_identifier => $item->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $item->barcode,
        'CheckInItemResponse returns correct item barcode with trap_hold_on_checkin = 1'
    );

    my $hold = Koha::Holds->find( $reserve_id );
    is( $hold->found, 'W', 'Hold with pickup at the checkin branch has been trapped as waiting' );

    # A hold with pickup at another branch is trapped in transit
    my $item_2 = $builder->build_sample_item( { library => $library->id } );

    my $reserve_id_2 = C4::Reserves::AddReserve(
        {
            branchcode     => $library_2->branchcode,
            borrowernumber => $patron_2->id,
            biblionumber   => $item_2->biblionumber,
            itemnumber     => $item_2->id,
            priority       => 1,
        }
    );

    $ncip_message = NCIPTest::render_fixture(
        'v2/CheckInItem.xml',
        {
            item_identifier => $item_2->barcode,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is(
        $dom->{NCIPMessage}->{CheckInItemResponse}->{UniqueItemId}->{ItemIdentifierValue}->{text},
        $item_2->barcode,
        'CheckInItemResponse returns correct item barcode for item with a hold for pickup at another branch'
    );

    my $hold_2 = Koha::Holds->find( $reserve_id_2 );
    is( $hold_2->found, 'T', 'Hold with pickup at another branch has been trapped in transit' );

    my $transfer = $item_2->get_transfer;
    ok( $transfer, 'Checkin has created a branch transfer for the trapped hold' );
    is( $transfer->tobranch, $library_2->branchcode, 'Transfer is to the hold pickup branch' );
};

$schema->storage->txn_rollback;
