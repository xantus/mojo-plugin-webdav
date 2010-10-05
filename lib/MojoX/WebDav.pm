package MojoX::WebDav;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::URL;
use Mojo::Asset::File;
use File::Copy;
use File::Path qw( mkpath rmtree );
use File::Spec;
use Data::Dumper;
use Mojo::ByteStream 'b';

use Fcntl qw( O_RDWR O_CREAT S_ISDIR );
use HTTP::Date qw( time2str time2isoz );
use bytes;

__PACKAGE__->attr( [qw/ mtfnpy /] );
__PACKAGE__->attr( cfg     => sub { {} } );
__PACKAGE__->attr( methods     => sub { [ qw( OPTIONS GET HEAD PROPFIND DELETE PUT COPY LOCK UNLOCK MOVE POST TRACE MKCOL ) ] } );

sub register {
    my ( $self, $c ) = @_;

    my $app = $ENV{MOJO_APP};

    return $self if $self->{configured}++;

    my $base = $self->cfg->{base} ||= '/dav';

    $app->routes->route( $base.'/(*url)' )->via( $self->methods )->to({ cb => sub { $self->_handle_req( @_ ); } });

    return $self;
}

sub _handle_req {
    my ( $self, $c ) = @_;

    $c->stash( dav_req => 1 );

    $c->res->headers->header( 'DAV' => '1,2,<http://apache.org/dav/propset/fs/1>' );
    $c->res->headers->header( 'Vary' => 'Accept-Encoding' );

    if ( $c->req->headers->header( 'X-Litmus' ) ) {
        $c->app->log->debug( 'Litmus test request' );
    }

    my $cmd = "cmd_". lc $c->req->method;

    if ( my $x = UNIVERSAL::can( $self, $cmd ) ) {
        my $path = File::Spec->catdir($c->app->static->root, split '/', ($c->req->url->path || ''));
        $x->( $self, $c, $path );
    } else {
        # not implemented
        $self->render_error( $c, 501 );
    }

    return;
}

*cmd_lock = *not_impl;
*cmd_unlock = *not_impl;
*cmd_post = *not_impl;
*cmd_trace = *not_impl;

sub not_impl {
    my ( $self, $c, $path ) = @_;

    warn "not implemented\n";

    $self->render_error( $c, 501 );
}

sub cmd_put {
    my ( $self, $c, $path ) = @_;

    return $self->render_error( $c, 403 ) unless $c->req->headers->content_length;

    # TODO check if $c->req has the asset we can move

    my $asset = Mojo::Asset::File->new( path => $path );
    $asset->add_chunk( $c->req->body );
    $asset->cleanup(0);

    # created
    $c->res->code( 201 );
    $c->res->body('');
    $c->rendered;
}

sub cmd_mkcol {
    my ( $self, $c, $path ) = @_;

    # unsupported media type
    return $self->render_error( $c, 415 ) if $c->req->headers->content_length;

    if ( !-e $path ) {
        unless( mkpath( $path, 0, 0755 ) ) {
            return $self->render_error( $c, 405 );
        }
        $c->res->code( 201 );
        $c->res->body('');
        $c->rendered;
    } else {
        $self->render_error( $c, 409 );
    }
}

sub cmd_move {
    my ( $self, $c, $path ) = @_;

    return $self->render_error( $c, 403 ) unless my $dest = $c->app->static->root->rel_dir( $c->req->headers->header( 'Destination' ) );
    my $u = Mojo::URL->new( $dest )->path;

    $dest = $c->app->static->root->rel_dir( $u );

    my $over = ( $c->req->headers->header( 'Overwrite' ) || '' ) eq 'T' ? 1 : 0;
    warn "move $path to ($u) $dest   over: $over\n";

    return $self->render_error( $c, 404 ) unless -e $path;

    if ( -d $dest && $over ) {
        # XXX if -d $dest and $over, do we rmtree and move?
        return $self->render_error( $c, 403 ); # XXX not authorized
    } elsif ( -d $dest ) {
        # dest not plain
        return $self->render_error( $c, 412 );
    }

    if ( -e $dest && !$over ) {
        # dest exists
        $self->render_error( $c, 412 );
    } else {
        warn "moving $path to $dest\n";
        File::Copy::move( $path, $dest ) or die "can't move $path to $dest : $!\n";
        $c->res->code( $over ? 204 : 201 );
        $c->res->body('');
        $c->rendered;
    }
}

sub cmd_copy {
    my ( $self, $c, $path ) = @_;

    return $self->render_error( $c, 403 ) unless my $dest = $c->app->static->root->rel_dir( $c->req->headers->header( 'Destination' ) );
    my $u = Mojo::URL->new( $dest )->path;

    $dest = $c->app->static->root->rel_dir( $u );

    my $over = ( $c->req->headers->header( 'Overwrite' ) || '' ) eq 'T' ? 1 : 0;
    warn "copy $path to ($u) $dest   over: $over\n";

    # XXX or 404?
    return $self->render_error( $c, 409 ) unless -e $path;

    if ( -d $dest && $over ) {
        # XXX if -d $dest and $over, do we rmtree and move?
        return $self->render_error( $c, 403 ); # XXX not authorized
    } elsif ( -d $dest ) {
        # dest not plain
        return $self->render_error( $c, 412 );
    }

    if ( -e $dest && !$over ) {
        # dest exists
        $self->render_error( $c, 412 );
    } else {
        warn "moving $path to $dest\n";
        File::Copy::copy( $path, $dest ) or die "can't move $path to $dest : $!\n";
        $c->res->code( $over ? 204 : 201 );
        $c->res->body('');
        $c->rendered;
    }
}

sub cmd_delete {
    my ( $self, $c, $path ) = @_;

    # XXX or 404?
    return $self->render_error( $c, 404 ) unless -e $path;
    return $self->render_error( $c, 403 ) if $path =~ m/\.$/;

    if ( -d $path ) {
        unless( rmtree( $path ) ) {
            return $self->render_error( $c, 405 );
        }
        $c->res->code( 201 );
        $c->res->body('');
        $c->rendered;
    } else {
        unless( unlink( $path ) ) {
            warn "could not unlink $path, $!\n";
            # permission denied
            $self->render_error( $c, 403 );
            return;
        }
    }

    # no content, aka success
    $c->res->code( 204 );
    $c->res->body('');
    $c->rendered;
}

sub cmd_options {
    my ( $self, $c ) = @_;

    my $rsh = $c->res->headers;

    $rsh->header( 'DAV' => '1,2,<http://apache.org/dav/propset/fs/1>' );
    $rsh->header( 'MS-Author-Via' => 'DAV' );
    $rsh->header( 'Allow'         => join( ',', @{$self->methods} ) );
    $rsh->header( 'Content-Type'  => 'httpd/unix-directory' );
    $c->res->code( 200 );
    $c->res->body('');
    $c->rendered;
}

sub cmd_get {
    my ( $self, $c ) = @_;

    $c->app->static->serve( $c, $c->req->url->path );
}

sub cmd_head {
    my ( $self, $c ) = @_;

    warn "head request\n";

    $c->app->static->serve( $c, $c->req->url->path );
}


sub render_error {
    my ( $self, $c, $code ) = @_;

    my $res = $c->res;

    return if ($res->code || '') eq $code;
    $res->code( $code );

    $res->headers->content_type('text/html');
    $res->body(qq|
<!doctype html><html>
    <head><title>Error $code</title></head>
    <body><h2>Error $code</h2></body>
</html>
|);

    $c->rendered;

    return;
}

1;

