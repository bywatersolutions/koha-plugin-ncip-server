#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 5;
use Test::Mojo;

use NCIPTest;

# From Koha
use C4::Context;
use C4::Accounts;
use Koha::Database;
use Koha::Libraries;
use Koha::Patrons;
use Koha::Holds;
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

subtest 'Test RequestItem with valid user and valid item' => sub {
    plan tests => 4;

    my $ncip_message = NCIPTest::render_fixture(
        'v2/RequestItem.xml',
        {
            user_identifier   => $patron_1->cardnumber,
            biblionumber      => $item_1->biblionumber,
            pickup_branchcode => $item_1->holdingbranch,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    my $hold_id = $dom->{NCIPMessage}->{RequestItemResponse}->{RequestId}->{RequestIdentifierValue}->{text};
    ok( $hold_id, "RequestItemResponse returned a request id" );

    my $hold = Koha::Holds->find( $hold_id );
    ok( $hold, "Request id is valid" );

    is( $item_1->biblionumber, $hold->biblionumber, "Request with matching id is for the correct record" );
    is( $patron_1->id, $hold->borrower->id, "Request with matching id is for the correct patron" );
};

subtest 'Test RequestItem with valid user and invalid item' => sub {
    plan tests => 4;

    my $ncip_message = NCIPTest::render_fixture(
        'v2/RequestItem.xml',
        {
            user_identifier   => $patron_1->cardnumber,
            biblionumber      => 'INVALID_BIBLIONUMBER',
            pickup_branchcode => $item_1->holdingbranch,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemDetail}->{text}, 'Record is not known.', "RequestItemResponse for invalid item returns correct ProblemDetail" );
    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemValue}->{text}, 'INVALID_BIBLIONUMBER', "RequestItemResponse for invalid item returns correct ProblemValue" );
    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemElement}->{text}, 'SYSNUMBER', "RequestItemResponse for invalid item returns correct ProblemElement" );
    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemType}->{text}, 'Unknown Record', "RequestItemResponse for invalid system number returns correct ProblemType" );
};

subtest 'Test RequestItem with invalid user and valid item' => sub {
    plan tests => 4;

    my $ncip_message = NCIPTest::render_fixture(
        'v2/RequestItem.xml',
        {
            user_identifier   => 'INVALID_PATRON_CARDNUMBER',
            biblionumber      => $item_1->biblionumber,
            pickup_branchcode => $item_1->holdingbranch,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemDetail}->{text}, 'User is not known.', "RequestItemResponse for invalid item returns correct ProblemDetail" );
    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemValue}->{text}, 'INVALID_PATRON_CARDNUMBER', "RequestItemResponse for invalid item returns correct ProblemValue" );
    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemElement}->{text}, 'UserIdentifierValue', "RequestItemResponse for invalid item returns correct ProblemElement" );
    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemType}->{text}, 'Unknown User', "RequestItemResponse for invalid item returns correct ProblemType" );
};

subtest 'Test RequestItem with invalid user and valid item' => sub {
    plan tests => 4;

    my $ncip_message = NCIPTest::render_fixture(
        'v2/RequestItem.xml',
        {
            user_identifier   => $patron_1->cardnumber,
            biblionumber      => $item_1->biblionumber,
            pickup_branchcode => 'INVALID_BRANCHCODE',
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemDetail}->{text}, 'The library from which the item is requested is not known.', "RequestItemResponse for invalid item returns correct ProblemDetail" );
    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemValue}->{text}, 'INVALID_BRANCHCODE', "RequestItemResponse for invalid item returns correct ProblemValue" );
    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemElement}->{text}, 'ToAgencyId', "RequestItemResponse for invalid item returns correct ProblemElement" );
    is( $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemType}->{text}, 'Unknown Agency', "RequestItemResponse for invalid item returns correct ProblemType" );
};

subtest 'Test RequestItem with valid user and valid item' => sub {
    plan tests => 3;

    C4::Context->set_preference('maxoutstanding', 1);

    my $account = $patron_1->account;
    my $accountline = $account->add_debit(
        {
            interface => 'commandline',
            amount      => '999.99',
            type        => 'MANUAL',
            description => "Test fee",
            note        => "Test fee note",
        }
    );

    is( ref $accountline, 'Koha::Account::Line', "Got back accountline" );

    my $ncip_message = NCIPTest::render_fixture(
        'v2/RequestItem.xml',
        {
            user_identifier   => $patron_1->cardnumber,
            biblionumber      => $item_1->biblionumber,
            pickup_branchcode => $item_1->holdingbranch,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $ncip_message );

    my $problem_type = $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemType}->{text};
    ok( $problem_type, "User Blocked" );

    my $problem_detail = $dom->{NCIPMessage}->{RequestItemResponse}->{Problem}->{ProblemDetail}->{text};
    ok( $problem_detail, "User owes too much." );
};

$schema->storage->txn_rollback;
