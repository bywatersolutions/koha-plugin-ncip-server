package Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler;
#
#===============================================================================
#
#         FILE: Hander.pm
#
#  DESCRIPTION:
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Chris Cormack (rangi), chrisc@catalyst.net.nz
# ORGANIZATION: Koha Development Team
#      VERSION: 1.0
#      CREATED: 19/09/13 10:43:14
#     REVISION: ---
#===============================================================================

# Copyright 2014 Catalyst IT <chrisc@catalyst.net.nz>

# This file is part of NCIPServer
#
# NCIPServer is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# NCIPServer is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with NCIPServer; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=head1 NAME

    Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler

=head1 SYNOPSIS

    use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler;
    my $handler = Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler->new( { namespace    => $namespace,
                                        type         => $request_type,
                                        ils          => $ils,
                                        template_dir => $templates
                                       } );

=head1 FUNCTIONS
=cut

use Modern::Perl;
use Template;

use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::AcceptItem;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::CancelRequestItem;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::CheckInItem;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::CheckOutItem;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::DeleteItem;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::LookupItem;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::LookupUser;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::LookupVersion;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::RenewItem;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::RequestItem;

# The request type comes straight from the incoming XML, so it must be
# checked against the list of handlers we actually provide rather than
# used to load an arbitrary class
my %SUPPORTED_TYPES = map { $_ => 1 } qw(
    AcceptItem
    CancelRequestItem
    CheckInItem
    CheckOutItem
    DeleteItem
    LookupItem
    LookupUser
    LookupVersion
    RenewItem
    RequestItem
);

=head2 new()

    Set up a new handler object, this will actually create one of the request type
    eg Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::LookupUser

=cut

sub new {
    my $class  = shift;
    my $params = shift;

    die "Unsupported NCIP request type '$params->{type}'\n"
        unless $SUPPORTED_TYPES{ $params->{type} };

    my $subclass = __PACKAGE__ . "::" . $params->{type};

    my $self = bless {
        type         => $params->{type},
        namespace    => $params->{namespace},
        ils          => $params->{ils},
        config       => $params->{config},
        ncip_version => $params->{ncip_version},
        templates    => $params->{template_dir},
    }, $subclass;

    return $self;
}

=head2 type

=cut

sub type { $_[0]->{type} }

=head2 namespace

=cut

sub namespace { $_[0]->{namespace} }

=head2 ils

=cut

sub ils { $_[0]->{ils} }

=head2 templates

=cut

sub templates { $_[0]->{templates} }

=head2 find_nodes

    my $nodes = $self->find_nodes( '//ItemId/ItemIdentifierValue', $context );

    Version-aware XPath lookup. Takes an unprefixed path, for NCIP version 2
    every element step is given the 'ns' namespace prefix, for version 1
    ( which has no namespace ) the path is used as is. Returns whatever
    XPathContext find() returns, a NodeList in scalar context.

=cut

sub find_nodes {
    my ( $self, $path, $context ) = @_;

    if ( $self->{ncip_version} != 1 ) {
        $path =~ s{(?<=/)(?=\w)}{ns:}g;
        $path =~ s{^(?=\w)}{ns:};
    }

    return $self->xpc->find( $path, $context );
}

=head2 text_of

    my $text = $self->text_of( '//MediumType', $context );

    Text content of the first node matching the version-aware path, or undef
    if there is no match. Prefers the text of a Value child when one exists,
    so scheme/value pairs and simple values both give back the plain value.

=cut

sub text_of {
    my ( $self, $path, $context ) = @_;

    my ($node) = $self->find_nodes( $path, $context )->get_nodelist;
    return unless $node;

    my ($value) = $self->find_nodes( 'Value', $node )->get_nodelist;
    return $value ? $value->textContent() : $node->textContent();
}

=head2 xpc()

    Give back an XPathContext Object, registered to the correct namespace

=cut

sub xpc {
    my $self = shift;
    my $xpc  = XML::LibXML::XPathContext->new;
    $xpc->registerNs( 'ns', $self->namespace() );
    return $xpc;
}

=head2 get_user_elements($xml)

    my $elements = get_user_elements( $xml );

    When passed an xml dom, this will find the user elements and pass convert them into an arrayref

=cut

sub get_user_elements {
    my ( $self, $xmldoc ) = @_;

    my $xpc = $self->xpc();
    my $ns = $self->{ncip_version} == 1 ? q{} : q{ns:};

    my $root = $xmldoc->documentElement();
    my @elements =
      $xpc->findnodes( '//' . $ns . 'LookupUser/UserElementType/Value', $root );
    unless ( $elements[0] ) {
        @elements = $xpc->findnodes( '//' . $ns . 'UserElementType', $root );
    }

    return \@elements;
}

=head2 get_item_elements($xml)

    my $elements = $self->get_item_element( $xml );

    When passed an xml dom, this will find the item elements and pass convert them into an arrayref

=cut

sub get_item_elements {
    my $self   = shift;
    my $xmldoc = shift;
    my $xpc    = $self->xpc();

    my $root = $xmldoc->documentElement();
    my @elements =
      $xpc->findnodes( '//ns:LookupItem/ItemElementType/Value', $root );
    unless ( $elements[0] ) {
        @elements = $xpc->findnodes( '//ns:ItemElementType', $root );
    }
    return \@elements;
}

=head2 get_agencies

    my ( $to, $from ) = $self->get_agencies( $xml );

    Takes an xml dom and returns an array containing the id of the agency the message
    is from and the id of the agency the message is to.

=cut

sub get_agencies {
    my ( $self, $xmldoc ) = @_;

    my $ncip_version = $self->{ncip_version};

    my $xpc = XML::LibXML::XPathContext->new;
    $xpc->registerNs( 'ns', $self->namespace() );

    my $root = $xmldoc->documentElement();

    my ( $from, $to );

    if ( $ncip_version == 1 ) {
        $from = $xpc->find( '//InitiationHeader/FromAgencyId/UniqueAgencyId/Value', $root );
        $to   = $xpc->find( '//InitiationHeader/ToAgencyId/UniqueAgencyId/Value',   $root );
    }
    else {
        $from = $xpc->find( '//ns:FromAgencyId', $root );
        $to   = $xpc->find( '//ns:ToAgencyId',   $root );
    }

    return ( $from, $to );
}

sub render_output {
    my ( $self, $template_name, $vars ) = @_;

    my $ncip_version = $self->{ncip_version};

    #$ncip_version ||= 2; # Default to assume NCIP version 2

    $vars->{ncip_version} = $ncip_version;

    my $template = Template->new(
        {
            INCLUDE_PATH => $self->templates,
            POST_CHOMP   => 1
        }
    ) || die Template->error();
    my $output;
    $template->process( "v$ncip_version/$template_name", $vars, \$output )
      || die $template->error();
    return $output;
}
1;
