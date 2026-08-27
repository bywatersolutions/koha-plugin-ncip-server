#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 2;
use Test::Mojo;

use NCIPTest;

# From Koha
use C4::Circulation;
use Koha::Database;
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

my $library = Koha::Libraries->search()->next();

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

$schema->storage->txn_rollback;
