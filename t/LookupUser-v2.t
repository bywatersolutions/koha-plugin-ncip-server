#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 13;
use Test::Mojo;

use NCIPTest;

# From Koha
use Koha::Database;
use t::lib::Mocks;
use t::lib::TestBuilder;

use_ok('Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP');
use_ok('Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler');

my $schema = Koha::Database->schema;
$schema->storage->txn_begin;
my $builder = t::lib::TestBuilder->new;
my $dbh     = C4::Context->dbh;

# Start transaction
$dbh->{RaiseError} = 1;

my $plugin = NCIPTest::install_plugin();

my %koha_config = (
    lookup_user_id     => 'cardnumber',
    format_ValidToDate => undef,
);
NCIPTest::set_config( $plugin, { koha => \%koha_config } );

my $t = Test::Mojo->new('Koha::REST::V1');

my $dom;

my $tx = $t->ua->get('/api/v1/contrib/ncip_server/ncip');
is( $tx->res->code, 200, "GET / is found" );

$dom = NCIPTest::post_ncip($t);
is(
    $dom->{NCIPMessage}->{xmlns},
    'http://www.niso.org/2008/ncip',
    "Got correct default xmlns"
);
is(
    $dom->{NCIPMessage}->{version},
    'http://www.niso.org/schemas/ncip/v2_02/ncip_v2_02.xsd',
    "Got correct xml version"
);

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
my $patron_1 = $builder->build_object(
    {
        class => 'Koha::Patrons',
        value => {
            surname      => 'Hall',
            firstname    => 'Kyle',
            userid       => 'khall',
            categorycode => $patron_category->{categorycode},
            dateexpiry   => '2032-12-31',
        }
    }
);

my $lookupuser = NCIPTest::render_fixture(
    'v2/LookupUser.xml',
    {
        user_identifier => $patron_1->cardnumber,
    }
);

subtest 'LookupUser: Test setting "lookup_user_id"' => sub {
    plan tests => 6;

    $dom = NCIPTest::post_ncip( $t, $lookupuser );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserId}
          ->{UserIdentifierValue}->{text},
        $patron_1->cardnumber,
        'LookupUserResponse returns cardnumber for lookup_user_id => cardnumber'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{NameInformation}->{PersonalNameInformation}
          ->{StructuredPersonalUserName}->{GivenName}->{text},
        'Kyle', 'LookupUserResponse has correct first name'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{NameInformation}->{PersonalNameInformation}
          ->{StructuredPersonalUserName}->{Surname}->{text},
        'Hall', 'LookupUserResponse has correct last name'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{UserPrivilege}->[2]->{ValidToDate}->{text},
        '2032-12-31',
        'LookupUserResponse has correct ValidToDate date and default format'
    );

    $koha_config{lookup_user_id} = 'userid';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
    $dom = NCIPTest::post_ncip( $t, $lookupuser );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserId}
          ->{UserIdentifierValue}->{text},
        'khall',
        'LookupUserResponse returns userid for lookup_user_id => userid'
    );

    $koha_config{lookup_user_id} = 'same';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
    $dom = NCIPTest::post_ncip( $t, $lookupuser );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserId}
          ->{UserIdentifierValue}->{text},
        $patron_1->cardnumber,
	'LookupUserResponse returns cardnumber for lookup_user_id => same, cardnumber sent in query'
    );

    # Reset lookup_user_id
    $koha_config{lookup_user_id} = 'cardnumber';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
};

subtest 'LookupUser: Test setting "format_ValidToDate"' => sub {
    plan tests => 1;

    $koha_config{format_ValidToDate} = '%Y-%d-%mT%H-%M-%S';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
    $dom = NCIPTest::post_ncip( $t, $lookupuser );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{UserPrivilege}->[2]->{ValidToDate}->{text},
        '2032-31-12T00-00-00',
        'LookupUserResponse has correct ValidToDate date and default format'
    );

    # Reset format_ValidToDate
    $koha_config{format_ValidToDate} = undef;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
};

subtest 'Test ability to strip DOCTYPE lines' => sub {
    plan tests => 4;

    # Minify xml
    $lookupuser =~ s/>\s+</></g;
    $lookupuser =~ s/[\r\n]+$//g;

    $dom = NCIPTest::post_ncip( $t, $lookupuser );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserId}
          ->{UserIdentifierValue}->{text},
        $patron_1->cardnumber,
        'LookupUserResponse returns cardnumber for lookup_user_id => cardnumber'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{NameInformation}->{PersonalNameInformation}
          ->{StructuredPersonalUserName}->{GivenName}->{text},
        'Kyle', 'LookupUserResponse has correct first name'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{NameInformation}->{PersonalNameInformation}
          ->{StructuredPersonalUserName}->{Surname}->{text},
        'Hall', 'LookupUserResponse has correct last name'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{UserPrivilege}->[2]->{ValidToDate}->{text},
        '2032-12-31',
        'LookupUserResponse has correct ValidToDate date and default format'
    );
};

subtest 'LookupUser: Test authentication via AuthenticationInput' => sub {
    plan tests => 6;

    my $user_password = 'Th3 Tr$th 1s 0u7 7h3r3';
    $patron_1->set_password( { password => $user_password, skip_validation => 1 } );

    my $lookupuser_with_pin = NCIPTest::render_fixture(
        'v2/LookupUser.xml',
        {
            user_identifier => $patron_1->cardnumber,
            user_password   => $user_password,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $lookupuser_with_pin );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserId}
          ->{UserIdentifierValue}->{text},
        $patron_1->cardnumber,
        'LookupUserResponse returns cardnumber for correct barcode and PIN'
    );
    ok(
        !exists $dom->{NCIPMessage}->{LookupUserResponse}->{Problem},
        'LookupUserResponse has no Problem element for correct barcode and PIN'
    );

    my $lookupuser_wrong_pin = NCIPTest::render_fixture(
        'v2/LookupUser.xml',
        {
            user_identifier => $patron_1->cardnumber,
            user_password   => 'Th3 Wr0ng P1n',
        }
    );

    $dom = NCIPTest::post_ncip( $t, $lookupuser_wrong_pin );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{Problem}->{ProblemType}->{text},
        'User Authentication Failed',
        'LookupUserResponse has correct problem type for wrong PIN'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{Problem}->{ProblemDetail}->{text},
        'Barcode Id or Password are invalid',
        'LookupUserResponse has correct problem detail for wrong PIN'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{Problem}->{ProblemElement}->{text},
        'Password',
        'LookupUserResponse has correct problem element for wrong PIN'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{Problem}->{ProblemValue}->{text},
        'Th3 Wr0ng P1n',
        'LookupUserResponse has correct problem value for wrong PIN'
    );
};

subtest 'LookupUser: Test setting "lookup_user_id" => "borrowernumber"' => sub {
    plan tests => 1;

    my $lookupuser_by_cardnumber = NCIPTest::render_fixture(
        'v2/LookupUser.xml',
        {
            user_identifier => $patron_1->cardnumber,
        }
    );

    $koha_config{lookup_user_id} = 'borrowernumber';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
    $dom = NCIPTest::post_ncip( $t, $lookupuser_by_cardnumber );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserId}
          ->{UserIdentifierValue}->{text},
        $patron_1->borrowernumber,
        'LookupUserResponse returns borrowernumber for lookup_user_id => borrowernumber'
    );

    # Reset lookup_user_id
    $koha_config{lookup_user_id} = 'cardnumber';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
};

subtest 'LookupUser: Test setting "user_id_lookup_field"' => sub {
    plan tests => 2;

    $patron_1->set( { sort1 => 'NCIP-sort1-424242' } )->store;

    $koha_config{user_id_lookup_field} = 'sort1';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );

    my $lookupuser_by_sort1 = NCIPTest::render_fixture(
        'v2/LookupUser.xml',
        {
            user_identifier => 'NCIP-sort1-424242',
        }
    );

    $dom = NCIPTest::post_ncip( $t, $lookupuser_by_sort1 );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserId}
          ->{UserIdentifierValue}->{text},
        $patron_1->cardnumber,
        'LookupUserResponse finds the patron by sort1 for user_id_lookup_field => sort1'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{NameInformation}->{PersonalNameInformation}
          ->{StructuredPersonalUserName}->{Surname}->{text},
        'Hall', 'LookupUserResponse has correct last name for patron found by sort1'
    );

    # Reset user_id_lookup_field
    delete $koha_config{user_id_lookup_field};
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
};

subtest 'LookupUser: Test setting "do_not_include_user_identifier_primary_key"' => sub {
    plan tests => 3;

    my $lookupuser_by_cardnumber = NCIPTest::render_fixture(
        'v2/LookupUser.xml',
        {
            user_identifier => $patron_1->cardnumber,
        }
    );

    $dom = NCIPTest::post_ncip( $t, $lookupuser_by_cardnumber );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{UserId}->{UserIdentifierType}->{text},
        'Primary Key',
        'UserOptionalFields has the Primary Key UserId by default'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{UserId}->{UserIdentifierValue}->{text},
        $patron_1->borrowernumber,
        'The Primary Key UserId contains the borrowernumber'
    );

    $koha_config{do_not_include_user_identifier_primary_key} = 1;
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
    $dom = NCIPTest::post_ncip( $t, $lookupuser_by_cardnumber );
    ok(
        !exists $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}->{UserId},
        'UserOptionalFields has no UserId for do_not_include_user_identifier_primary_key => 1'
    );

    # Reset do_not_include_user_identifier_primary_key
    delete $koha_config{do_not_include_user_identifier_primary_key};
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
};

subtest 'LookupUser: Test unknown user problem response' => sub {
    plan tests => 4;

    my $lookupuser_unknown = NCIPTest::render_fixture(
        'v2/LookupUser.xml',
        {
            user_identifier => 'NCIP-no-such-user-424242',
        }
    );

    $dom = NCIPTest::post_ncip( $t, $lookupuser_unknown );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{Problem}->{ProblemType}->{text},
        'Unknown User',
        'LookupUserResponse has correct problem type for an unknown user'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{Problem}->{ProblemDetail}->{text},
        'User is not known',
        'LookupUserResponse has correct problem detail for an unknown user'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{Problem}->{ProblemElement}->{text},
        'UserId',
        'LookupUserResponse has correct problem element for an unknown user'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{Problem}->{ProblemValue}->{text},
        'NCIP-no-such-user-424242',
        'LookupUserResponse has correct problem value for an unknown user'
    );
};

$schema->storage->txn_rollback;
