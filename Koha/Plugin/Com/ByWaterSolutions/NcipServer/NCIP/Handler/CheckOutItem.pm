package Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::CheckOutItem;

=head1

  Koha::Plugin::Com::ByWaterSolutions::NcipServer::NCIP::Handler::CheckOutItem

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

    my $config = $self->{config}->{koha};

    if ($xmldoc) {
        my $root = $xmldoc->documentElement();

        my $userid   = $self->find_nodes( '//UserIdentifierValue', $root );
        my $itemid   = $self->find_nodes( '//ItemIdentifierValue', $root );
        my $date_due = $self->find_nodes( '//DesiredDateDue',      $root );

        # checkout the item
        my $data = $self->ils->checkout( $userid, $itemid, $date_due, $config );

        my ( $from, $to ) = $self->get_agencies($xmldoc);

        if ( $data->{success} ) {
            my $elements = $self->get_user_elements($xmldoc);
            return $self->render_output(
                'response.tt',
                {
                    message_type => 'CheckOutItemResponse',
                    from_agency  => $to,
                    to_agency    => $from,
                    barcode      => $itemid,
                    userid       => $userid,
                    elements     => $elements,
                    datedue      => $data->{date_due},
                    config       => $config,
                }
            );
        }
        else {
            return $self->render_output(
                'problem.tt',
                {
                    message_type => 'CheckOutItemResponse',
                    problems     => $data->{problems},
                    from_agency  => $to,
                    to_agency    => $from,
                }
            );
        }
    }
}

1;
