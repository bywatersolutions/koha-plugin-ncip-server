package Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::RequestItem;

=head1

  Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::RequestItem

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

        my $branchcode;

        my ($userid) = $self->find_nodes( '//UserIdentifierValue', $root )->get_nodelist;
        $userid = $userid->textContent() if $userid;

        my ($itemid) = $self->find_nodes( '//ItemIdentifierValue', $root )->get_nodelist;
        $itemid = $itemid->textContent() if $itemid;

        my ($identifier) = $self->find_nodes( '//BibliographicRecordIdentifier', $root )->get_nodelist;
        $identifier = $identifier->textContent() if $identifier;

        my $bib_item_id_code = $self->find_nodes( '//BibliographicItemIdentifierCode', $root );
        if ( $bib_item_id_code eq 'ISBN' ) {
            ($identifier) = $self->find_nodes( '//BibliographicItemIdentifier', $root )->get_nodelist;
            $identifier = $identifier->textContent();
        };

        my $type = $bib_item_id_code || 'SYSNUMBER';

        my ( $from, $to ) = $self->get_agencies($xmldoc);

        $branchcode = $to->[0]->textContent() if $to;

        my $config = $self->{config}->{koha};
        my $ignore_item_requests = $config->{ignore_item_requests};

        my $data;
        if ($ignore_item_requests) {
            $data = {
                success    => 1,
                request_id => 0,
            };
        }
        else {
            $data = $self->ils->request( $userid, $itemid, $identifier, $type, $branchcode, $config );
        }

        if ( $data->{success} ) {
            my $elements = $self->get_user_elements($xmldoc);
            return $self->render_output(
                'response.tt',
                {
                    message_type => 'RequestItemResponse',
                    from_agency  => $to,
                    to_agency    => $from,
                    barcode      => $itemid,
                    request_id   => $data->{request_id},
                    elements     => $elements,
                }
            );
        }
        else {
            return $self->render_output(
                'problem.tt',
                {
                    message_type => 'RequestItemResponse',
                    problems     => $data->{problems},
                    from_agency  => $to,
                    to_agency    => $from,
                }

            );
        }
    }
}

1;
