package Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::AcceptItem;

=head1

  Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::AcceptItem

=head1 SYNOPSIS

    Not to be called directly, Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler will pick the appropriate Handler 
    object, given a message type

=head1 FUNCTIONS

=cut

use Modern::Perl;

use Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler;

our @ISA = qw(Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler);

sub handle {
    my $self   = shift;
    my $xmldoc = shift;
    if ($xmldoc) {
        my $root = $xmldoc->documentElement();
        my $xpc  = $self->xpc();

        my $config = $self->{config}->{koha};

        my ( $itemid, $action, $request, $request_agency, $request_id,
            $user_id, $item_info );

        my $itemdata = {};

        $itemid = $self->find_nodes( '//ItemIdentifierValue', $root );
        $itemid = $self->find_nodes( '//RequestIdentifierValue', $root ) if $config->{request_identifier_value_as_barcode};

        $action = $self->text_of( '//RequestedActionType', $root );

        # The request agency and request id live in different structures
        # in the two protocol versions
        if ( $self->{ncip_version} == 1 ) {
            $request_agency =
              $xpc->find( '//FromAgencyId/UniqueAgencyId/Value', $root );
            $request_id = $xpc->find( '//RequestIdentifierValue', $root );
        }
        else {
            ($request) = $xpc->findnodes( '//ns:RequestId', $root );
            $request_agency = $xpc->find( 'ns:AgencyId', $request );
            $request_id = $xpc->find( '//ns:RequestIdentifierValue', $request );
        }

        $user_id   = $self->find_nodes( '//UserIdentifierValue', $root );
        $item_info = $self->find_nodes( '//ItemOptionalFields',  $root );

        if ( $item_info->[0] ) {
            my $bibliographic = $self->find_nodes( '//BibliographicDescription', $item_info->[0] );

            my $title = $self->text_of( '//Title', $bibliographic->[0] );
            $itemdata->{title} = $title if defined $title;

            my $author = $self->text_of( '//Author', $bibliographic->[0] );
            $itemdata->{author} = $author if defined $author;

            my $date = $self->text_of( '//PublicationDate', $bibliographic->[0] );
            $itemdata->{publicationdate} = $date if defined $date;

            my $publisher = $self->text_of( '//Publisher', $bibliographic->[0] );
            $itemdata->{publisher} = $publisher if defined $publisher;

            my $medium = $self->text_of( '//MediumType', $bibliographic->[0] );
            $itemdata->{mediumtype} = $medium if defined $medium;

            my $format = $self->text_of( '//Format', $bibliographic->[0] );
            if ( defined $format ) {
                my $itemtype = $config->{itemtype_map}->{$format};
                $itemdata->{itemtype} = $itemtype if $itemtype;
            }

            my $item_description = $self->find_nodes( '//ItemDescription', $item_info->[0] );
            if ($item_description) {
                my $itemcallnumber = $self->text_of( '//CallNumber', $item_description->[0] );
                $itemdata->{itemcallnumber} = $itemcallnumber if defined $itemcallnumber;
            }
        }

        my ( $from, $to ) = $self->get_agencies($xmldoc);

        # Autographics workflow is for an accept item i
        # to create the item then do what is in $action
        # my $create = 0;
        # if ( $from && $from =~ /CPomAG/ ) {
        #    $create = 1;
        # }
        my $create = 1;    # Same for Relais and Clio, just always create for now

        my $pickup_location;
        $pickup_location ||= $self->find_nodes( '//PickupLocation', $root );
        $pickup_location ||= $to->[0]->textContent() if $to && $to->[0];

        my $data =
          $self->ils->acceptitem( $itemid, $user_id, $action, $create,
            $itemdata, $pickup_location, $config );

        my $output;
        my $vars;

        # we switch these for the templates
        # because we are responding, to becomes from, from becomes to
        if ( !$data->{success} ) {
            $output = $self->render_output(
                'problem.tt',
                {
                    message_type => 'AcceptItemResponse',
                    problems     => $data->{problems},
                    from_agency    => $to,
                    to_agency      => $from,
                },
                $self->{ncip_version},
            );
        }
        else {
            my $elements = $self->get_user_elements($xmldoc);
            $output = $self->render_output(
                'response.tt',
                {
                    from_agency    => $to,
                    to_agency      => $from,
                    message_type   => 'AcceptItemResponse',
                    barcode        => $itemid,
                    request_agency => $request_agency,
                    requestid      => $request_id,
                    newbarcode     => $data->{'newbarcode'} || $itemid,
                    elements       => $elements,
                    accept         => $data,
                }
            );
        }
        return $output;
    }
}

1;
