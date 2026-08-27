package Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP;

use Modern::Perl;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use Template;
use Try::Tiny;
use XML::LibXML;

use Koha::Logger;

use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler;
use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::ILS::Koha;

use constant NAMESPACE => 'http://www.niso.org/2008/ncip';

our $VERSION           = '0.01';
our $strict_validation = 0;        # move to config file

=head1 NAME

    Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP

=head1 SYNOPSIS

    use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP;
    my $ncip = Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP->new();

=head1 FUNCTIONS

=cut

sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self = {
        namespace     => NAMESPACE,
        ils           => Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::ILS::Koha->new( name => 'Koha' ),
        templates_dir => abs_path( dirname(__FILE__) . '/templates' ),
    };

    return bless $self, $class;
}

=head2 namespace

=cut

sub namespace { $_[0]->{namespace} }

=head2 ils

=cut

sub ils { $_[0]->{ils} }

=head2 xmldoc

=cut

sub xmldoc { $_[0]->{xmldoc} }

=head2 templates_dir

=cut

sub templates_dir { $_[0]->{templates_dir} }

=head2 process_request()

 my $response = $ncip->process_request($xml);

=cut

sub process_request {
    my $self   = shift;
    my $xml    = shift;
    my $config = shift;

    my ( $request_type, $ncip_version ) = $self->handle_initiation($xml);
    $self->{ncip_protocol_version} = $ncip_version;

    unless ($request_type) {

      # We have invalid xml, or we can't figure out what kind of request this is
      # Handle error here
        my $output = $self->_error("We can't find request type");
        return $output;
    }

    my $handler = Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler->new(
        {
            namespace    => $self->namespace(),
            type         => $request_type,
            ils          => $self->ils,
            config       => $config,
            ncip_version => $ncip_version,
            template_dir => $self->templates_dir,
        }
    );

    return $handler->handle( $self->xmldoc );
}

=head2 handle_initiation

=cut

sub handle_initiation {
    my $self = shift;
    my $xml  = shift;
    my $dom;
    my $log = Koha::Logger->get( { category => 'plugin.ncipserver' } );
    eval { $dom = XML::LibXML->load_xml( string => $xml ); };
    if ($@) {
        $log->info("Invalid xml we can not parse it ");
    }

    if ($dom) {

        # should check validity with validate at this point
        if ( $strict_validation && !$self->validate($dom) ) {

            # we want strict validation, bail out if dom doesnt validate
            #            warn " Not valid xml";

            # throw/log error
            $log->error("INVALID XML DOM!");

            return ( undef, '2' ); # Hard code default of NCIP version 2
        }
        my ( $request_type, $ncip_version ) = $self->parse_request($dom);
        $log->info("REQUEST TYPE: $request_type") if $request_type;
        $log->info("NCIP VERSION: $ncip_version") if $ncip_version;

        # do whatever we should do to initiate, then hand back request_type
        if ($request_type) {
            $self->{xmldoc} = $dom;
            return ( $request_type, $ncip_version );
        }
    }
    else {
        $log->info("We have no DOM");

        return ( undef, '2' ); # Hard code default of NCIP version 2
    }
}

sub validate {

    # this should perhaps be in it's own module
    my $self = shift;
    my $dom  = shift;
    try {
        $dom->validate();
    }
    catch {
        return;
    };

    # we could validate against the schema here, might be good?
    # my $schema = XML::LibXML::Schema->new(string => $schema_str);
    # eval { $schema->validate($dom); }
    # perhaps we could check the ncip version and validate that too
    return 1;
}

sub parse_request {
    my $self = shift;
    my $dom  = shift;
    my $nodes =
      $dom->getElementsByTagName( 'NCIPMessage' );

    if ($nodes) {
        my $version = 1;
        if  ($nodes->[0]->hasAttributeNS($self->namespace(), 'version')) {
            $version = index($nodes->[0]->getAttributeNS($self->namespace(), 'version'), 'v2') != -1 ? 2 : 1;
        }
        elsif ($nodes->[0]->hasAttribute('version')) {
            $version = index($nodes->[0]->getAttribute('version'), 'v2') != -1 ? 2 : 1;
        }

        my @childnodes = $nodes->[0]->childNodes();
        # The message tag ( e.g. <LookupUser> ) location changes based on line breaks
        # so we need to check the first and second nodes to see where it is.
        # Weird, right?
        if ( $childnodes[0] && $childnodes[0]->localname() ) {
            return ( $childnodes[0]->localname(), $version );
        }
        elsif ( $childnodes[1] && $childnodes[1]->localname() ) {
            return ( $childnodes[1]->localname(), $version );
        }
        else {
            return;
        }
    }
    else {
        return;
    }
    return;
}

sub _error {
    my $self         = shift;
    my $ProblemDetail = shift;
    my $vars;
    $vars->{'ProblemDetail'} = $ProblemDetail;
    $vars->{'message_type'} =
      'ItemRequestedResponse';    # No idea what this type should be
    my $template = Template->new(
        { INCLUDE_PATH => $self->templates_dir, } );
    my $output;

    # There is no top level 'problem.tt' template, so this process call fails
    # and $output stays undef. The caller then falls back to the "It works!"
    # response, which clients probing the endpoint expect. Keep it that way.
    $template->process( 'problem.tt', $vars, \$output );
    return $output;
}
1;
