package Koha::Plugin::Com::ByWaterSolutions::NcipServer;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use Encode;
use JSON::Validator;
use Mojo::JSON qw(decode_json);
use Try::Tiny;
use YAML::XS;

use C4::Context;
use Koha::Config::SysPrefs;
use Koha::Database;
use Koha::Patrons;

our $VERSION = "0.0.0";

our $metadata = {
    name            => 'NCIP server plugin',
    author          => 'ByWater Solutions',
    date_authored   => '2025-04-25',
    date_updated    => "1970-01-01",
    minimum_version => '24.05',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'NCIP server implementation',
    namespace       => 'ncip_server',
};

=head1 Koha::Plugin::Com::ByWaterSolutions::NcipServer

NCIP server plugin

=head2 Plugin methods

=head3 new

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::NcipServer->new();

Constructor method for the plugin.

=cut

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

=head3 install

Migrates the NcipRequireToken and NcipToken system preferences used by the
standalone NCIP server into the plugin configuration, then deletes them.

=cut

sub install {
    my ($self) = @_;

    my $require_pref = Koha::Config::SysPrefs->find('NcipRequireToken');
    my $token_pref   = Koha::Config::SysPrefs->find('NcipToken');

    return 1 unless $require_pref || $token_pref;

    # Copy the syspref values into the plugin configuration and delete the
    # sysprefs in a single transaction so we never end up half-migrated
    my $schema = Koha::Database->new->schema;
    $schema->txn_do(
        sub {
            my $config = {};

            my $yaml = $self->retrieve_data('configuration');
            if ( defined $yaml && length $yaml ) {
                $config = YAML::XS::Load( Encode::encode_utf8($yaml) ) // {};
            }

            # Copy, but never clobber existing plugin configuration values
            $config->{token_required} = $require_pref->value ? 1 : 0
                if $require_pref && !exists $config->{token_required};
            $config->{auth_token} = $token_pref->value
                if $token_pref && !exists $config->{auth_token};

            $self->store_data( { configuration => Encode::decode_utf8( YAML::XS::Dump($config) ) } );

            $require_pref->delete if $require_pref;
            $token_pref->delete   if $token_pref;
        }
    );

    C4::Context->clear_syspref_cache();

    return 1;
}

=head3 uninstall

=cut

sub uninstall {
    return 1;
}

=head3 configure

Plugin configuration method

=cut

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'configure.tt' } );

    my @errors;
    my $configuration;

    if ( scalar $cgi->param('op') && scalar $cgi->param('op') eq 'cud-save' ) {

        $configuration = scalar $cgi->param('configuration');

        # Refuse to store configuration that is not valid YAML, the NCIP
        # endpoint would return errors until it is fixed
        my $parse_error;
        if ( defined $configuration && length $configuration ) {
            eval { YAML::XS::Load( Encode::encode_utf8($configuration) ) };
            $parse_error = $@;
        }

        if ($parse_error) {

            # Show the submitted text below so the edit is not lost, the
            # previously stored configuration remains in effect
            push @errors, { code => 'CONFIGURATION_NOT_SAVED' };
        }
        else {
            $self->store_data( { configuration => $configuration } );
            $configuration = undef;
        }
    }

    push @errors, @{ $self->check_configuration };

    $template->param(
        errors        => \@errors,
        configuration => $configuration // $self->retrieve_data('configuration'),
    );

    $self->output_html( $template->output() );
}

=head3 api_routes

Method that returns the API routes to be merged into Koha's

=cut

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

=head3 api_namespace

Method that returns the namespace for the plugin API to be put on

=cut

sub api_namespace {
    my ($self) = @_;

    return 'ncip_server';
}

=head2 Internal methods

=head3 check_configuration

    my $errors = $self->check_configuration;

Returns a reference to a list of errors found in configuration.

=cut

sub check_configuration {
    my ($self) = @_;

    my @errors;

    my $config = $self->configuration( { force => 1 } );
    return [ { code => 'CONFIGURATION_INVALID' } ] unless defined $config;

    # Validate the configuration structure against the JSON schema. This
    # catches misspelled keys, which otherwise silently do nothing, and
    # values of the wrong shape. The errors are advisory, the configuration
    # is stored either way.
    my $validator = JSON::Validator->new;
    $validator->coerce('booleans,numbers');
    $validator->schema( decode_json( $self->mbf_read('config_schema.json') ) );
    push @errors, map { { code => 'CONFIG_SCHEMA', error => "$_" } } $validator->validate($config);

    push @errors, { code => 'AUTH_TOKEN_MISSING' }
        if $config->{token_required} && !$config->{auth_token};

    my $borrowernumber = $config->{koha}->{userenv_borrowernumber};
    if ( !$borrowernumber ) {
        push @errors, { code => 'USERENV_NOT_SET' };
    }
    elsif ( !Koha::Patrons->find($borrowernumber) ) {
        push @errors, { code => 'USERENV_NOT_FOUND', borrowernumber => $borrowernumber };
    }

    return \@errors;
}

=head3 configuration

Accessor for the de-serialized plugin configuration

=cut

sub configuration {
    my ( $self, $params ) = @_;

    if ( !$self->{_configuration} || $params->{force} ) {

        my $yaml = $self->retrieve_data('configuration');

        if ( defined $yaml && length $yaml ) {
            eval { $self->{_configuration} = YAML::XS::Load( Encode::encode_utf8($yaml) ); };

            if ($@) {
                warn "[NCIP CONFIG ERROR]" . $@;
                return;
            }
        }

        $self->{_configuration} //= {};
    }

    return $self->{_configuration};
}

=head3 requires_token

    if ( $plugin->requires_token() ) { ... }

=cut

sub requires_token {
    my ($self) = @_;

    my $config = $self->configuration // {};

    return $config->{token_required} ? 1 : 0;
}

=head3 is_token_valid

    if ( $plugin->is_token_valid($token) ) { ... }

Compares the passed token with the configured one.

=cut

sub is_token_valid {
    my ($self, $token) = @_;

    my $config = $self->configuration // {};

    my $configured_token = $config->{auth_token} // '';

    return $configured_token eq $token;
}

1;
