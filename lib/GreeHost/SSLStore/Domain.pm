# ABSTRACT: Register & Renew Let's Encrypt SSL Certificates
package GreeHost::SSLStore::Domain;
use Moo;
use Module::Runtime qw( use_module );
use File::Path qw( make_path );
use IPC::Run3;

has name => (
    is => 'ro',
);

has domains => (
    is => 'ro',
);

# Linode DNS Stuff

has dns_linode_key => (
    is       => 'ro',
    required => 1,
);

has dns_linode_version => (
    is      => 'ro',
    default => sub { 4 },
);

has dns_credential_file => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { 
        my ( $self ) = @_;
        return sprintf( "/opt/greehost/sslstore/domains/%s/.credentials", $self->name ); 
    },
);

has domain_root => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { 
        my ( $self ) = @_;
        return sprintf( "/opt/greehost/sslstore/domains/%s", $self->name );
    },
);

has dns_credential_file_contents => (
    is      => 'ro',
    lazy    => 1,
    builder => sub {
        my ( $self ) = @_;
        return sprintf( "dns_linode_key = %s\ndns_linode_version = %d\n", 
            $self->dns_linode_key, $self->dns_linode_version );
    }
);

sub _write_credential_file {
    my ( $self ) = @_;
    
    open my $cfh, ">", $self->dns_credential_file
        or die "Failed to open " . $self->dns_credential_file . " for writing: $!";
    print $cfh $self->dns_credential_file_contents;
    close $cfh;

    return $self;
}

sub _remove_credential_file { 
    unlink shift->dns_credential_file;
}

sub install {
    my ( $self ) = @_;

    return 1 if -d $self->domain_root;

    make_path( $self->domain_root );
    $self->_write_credential_file;

    run3([ qw( docker run -v ), $self->domain_root . ":/etc/letsencrypt", qw( -v /var/lib/letsencrypt:/var/lib/letsencrypt ),
        qw( certbot/dns-linode certonly --register-unsafely-without-email --agree-tos --dns-linode ),
        qw( --dns-linode-credentials /etc/letsencrypt/.credentials --dns-linode-propagation-seconds 300 ),
        @{[ map { ( "-d", $_ ) } ( $self->name, @{$self->domains} ) ]},
    ]);

    $self->_remove_credential_file;

    return $self;
}

sub update {
    my ( $self ) = @_;

    # Redirect to installer
    return $self->install unless -d $self->domain_root;
    
    $self->_write_credential_file;
    run3([ qw( docker run -v ), $self->domain_root . ":/etc/letsencrypt", qw( -v /var/lib/letsencrypt:/var/lib/letsencrypt ),
        qw( certbot/dns-linode renew --register-unsafely-without-email --agree-tos --dns-linode ),
        qw( --dns-linode-credentials /etc/letsencrypt/.credentials --dns-linode-propagation-seconds 300 ),
    ]);
    $self->_remove_credential_file;

    return $self;
}

sub status {
    my ( $self ) = @_;

    run3([ qw( docker run -v ), $self->domain_root . ":/etc/letsencrypt", qw( -v /var/lib/letsencrypt:/var/lib/letsencrypt ),
        qw( certbot/dns-linode certificates ),
    ], \undef, \my $stdout, \my $stderr);
    $self->_remove_credential_file;

    my ($status) = values %{$self->_parse_certbot_certificate($stdout)};

    return $status;
}

sub _parse_certbot_certificate {
    my ( $self, $str ) = @_;

    my $status = {};
    my $name = "";
    foreach my $line ( split /\n/, $str ) {
        my ( $lhs, $rhs ) = split( /:/, $line, 2 );
        next unless $lhs && $rhs;
        s/^\s+//, s/\s+$// for $rhs;
        if ( $lhs =~ /^\s+Certificate Name$/ ) {
            $name = $rhs;
            $status->{$name} = {
                name      => $name,
                serial    => "",
                domains   => [qw()],
                expire    => "",
                cert_path => "",
                key_path  => "",
            };
        } elsif ( $lhs =~ /^\s+Serial Number$/ ) {
            $status->{$name}{serial} = $rhs;
        } elsif ( $lhs =~ /^\s+Domains$/ ) {
            push @{$status->{$name}{domains}}, split( /\s+/, $rhs);
        } elsif ( $lhs =~ /^\s+Expiry Date$/ ) {
            $status->{$name}{expire} = $rhs;
            if ( $rhs =~ /^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2}\+\d{2}:\d{2})\s+\(VALID:\s+(\d+)\s+days\)$/ ) {
                my ( $date, $time, $days ) = ( $1, $2, $3 );
                $status->{$name}{expire_moment} = Time::Moment->from_string( "${date}T${time}" );
                $status->{$name}{expire_days}   = $days;
            }
        } elsif ( $lhs =~ /^\s+Certificate Path$/ ) {
            $status->{$name}{cert_path} = $rhs;
        } elsif ( $lhs =~ /^\s+Private Key Path$/ ) {
            $status->{$name}{key_path} = $rhs;
        }
    }
    return $status;
}

1;
