#!/usr/bin/perl

use Modern::Perl;

use FindBin qw($Bin);
use lib ( "$Bin/lib", "$Bin/..", '/kohadevbox/koha' );

use Test::More tests => 8;
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
my $user_password = 'Th3 Tr$th 1s 0u7 7h3r3';
my $patron_1 = $builder->build_object(
    {
        class => 'Koha::Patrons',
        value => {
            surname      => 'Hall',
            firstname    => 'Kyle',
            categorycode => $patron_category->{categorycode},
            dateexpiry   => '2032-12-31',
	    password     => $user_password,
        }
    }
);
$patron_1->set_password( { password => $user_password, skip_validation => 1 } );

my $lookupuser = NCIPTest::render_fixture(
    'v1/LookupUser.xml',
    {
        user_identifier => $patron_1->cardnumber,
        user_password   => $user_password,
    }
);

subtest 'LookupUser: Test setting "lookup_user_id"' => sub {
    plan tests => 6;

    $dom = NCIPTest::post_ncip( $t, $lookupuser );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UniqueUserId}->{UserIdentifierValue}->{text},
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
        $dom->{NCIPMessage}->{LookupUserResponse}->{UniqueUserId}->{UserIdentifierValue}->{text},
        $patron_1->userid,
        'LookupUserResponse returns userid for lookup_user_id => userid'
    );

    $koha_config{lookup_user_id} = 'same';
    NCIPTest::set_config( $plugin, { koha => \%koha_config } );
    $dom = NCIPTest::post_ncip( $t, $lookupuser );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UniqueUserId}->{UserIdentifierValue}->{text},
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
        $dom->{NCIPMessage}->{LookupUserResponse}->{UniqueUserId}->{UserIdentifierValue}->{text},
        $patron_1->cardnumber,
        'LookupUserResponse returns cardnumber for lookup_user_id => cardnumber with DOCTYPE in message'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{NameInformation}->{PersonalNameInformation}
          ->{StructuredPersonalUserName}->{GivenName}->{text},
        'Kyle', 'LookupUserResponse has correct first name with DOCTYPE in message'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{NameInformation}->{PersonalNameInformation}
          ->{StructuredPersonalUserName}->{Surname}->{text},
        'Hall', 'LookupUserResponse has correct last name with DOCTYPE in message'
    );
    is(
        $dom->{NCIPMessage}->{LookupUserResponse}->{UserOptionalFields}
          ->{UserPrivilege}->[2]->{ValidToDate}->{text},
        '2032-12-31',
        'LookupUserResponse has correct ValidToDate date and default format with DOCTYPE in message'
    );
};

$schema->storage->txn_rollback;
