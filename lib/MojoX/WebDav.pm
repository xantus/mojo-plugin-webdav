package MojoX::WebDav;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::URL;
use Mojo::Asset::File;
use File::Copy::Recursive qw( rcopy rmove );
use File::Path qw( mkpath rmtree );
use File::Spec;
use Data::Dumper;
use Mojo::ByteStream 'b';

use Fcntl qw( O_RDWR O_CREAT S_ISDIR );
use HTTP::Date qw( time2str time2isoz );
use bytes;

__PACKAGE__->attr( [qw/ mtfnpy prefix root /] );
__PACKAGE__->attr( cfg     => sub { {} } );
__PACKAGE__->attr( methods     => sub { [ qw( GET HEAD OPTIONS PROPFIND DELETE PUT COPY LOCK UNLOCK MOVE POST TRACE MKCOL ) ] } );
__PACKAGE__->attr( allowed_methods => sub { join( ',', @{ shift->methods } ); });

sub register {
    my ( $self, $app ) = @_;

    return $self if $self->{configured}++;

    $self->root( '/dav' );
    $self->prefix( '/files' );

    $app->plugins->add_hook( before_dispatch => sub {
        $self->_handle_req( @_[ 1, $#_ ] );
    });

#    $app->plugins->add_hook( after_static_dispatch => sub {
#        return unless shift->stash( 'dav.request' );
#        # ...
#    });

    return $self;
}

sub _handle_req {
    my ( $self, $c ) = @_;

    my $path = $c->req->url->path->clone->canonicalize->to_string;

    # remove prefix
    if ( my $prefix = $self->prefix ) {
        return unless $path =~ s/^$prefix//;
    }

    $c->stash(
        'dav.request' => 1,
        'dav.absroot' => File::Spec->catdir( $c->app->static->root, $self->root ),
        'dav.root' => $self->root,
        'dav.path' => $path,
        'dav.prefix' => $self->prefix
    );

    $c->res->headers->header( 'DAV' => '1,2,<http://apache.org/dav/propset/fs/1>' );
    $c->res->headers->header( 'Vary' => 'Accept-Encoding' );

    if ( my $litmus = $c->req->headers->header( 'X-Litmus' ) ) {
        $c->app->log->debug( 'Litmus test request: '.$litmus );
#        warn $c->req->to_string;
    }

    my $cmd = "cmd_". lc $c->req->method;

    if ( my $x = UNIVERSAL::can( $self, $cmd ) ) {
        my $parts = Mojo::Path->new->parse($path)->parts;

        return $c->render_not_found if $parts->[0] eq '..';

        my $abs_path = File::Spec->catfile( $c->stash( 'dav.absroot' ), @$parts );
        $c->stash( 'dav.relpath' => File::Spec->catfile( $self->root, @$parts ) );
        $c->stash( 'dav.abspath' => $abs_path );

        $c->app->log->debug( "original path $path now, $abs_path" );

        $x->( $self, $c, $abs_path );
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
    my ( $self, $c ) = @_;

    $c->app->log->debug( "not implemented" );

    $self->render_error( $c, 501 );
}

sub cmd_put {
    my ( $self, $c, $path ) = @_;

    return $self->render_error( $c, 403 ) unless $c->req->headers->content_length;

    # TODO check if $c->req has the asset we can move

    if ( -d $path ) {
        # 8.7.2
        return $self->render_error( $c, 409 );
    }

    my $asset = Mojo::Asset::File->new( path => $path );
    $asset->add_chunk( $c->req->body );
    $asset->cleanup(0);

    # created
    $c->render_text( 'Created', status => 201 );
}

sub cmd_mkcol {
    my ( $self, $c, $path ) = @_;

    # 8.3.1
    return $self->render_error( $c, 403 ) if -e $c->stash( 'dav.path' ) eq '/';

    return $self->render_error( $c, 415 ) if $c->req->headers->content_length;

    return $self->render_error( $c, 405 ) if -e $path;

    return $self->render_error( $c, 409 ) unless mkdir( $path, 0755 );

    $c->render_text( 'Created', status => 201 );
}

sub cmd_move {
    my ( $self, $c, $path ) = @_;

    return $self->render_error( $c, 400 ) unless my $dest = $self->_get_dest( $c );

    my $over = ( $c->req->headers->header( 'Overwrite' ) || '' ) eq 'T' ? 1 : 0;

#    my $depth = $c->req->headers->header( 'Depth' );
#    $depth = defined $depth && $depth == 0 ? 0 : 1;

    # 8.9.4
    return $c->render_error( $c, 403 ) if $path eq $dest;

    return $c->render_not_found unless -e $path;

    my $replaced = -e $dest;

    # 8.9.3
    if ( -d $dest ) {
        if ( $over ) {
            return $self->render_error( $c, 412 ) unless rmtree( $dest, { safe => 1 } );
            # fall through to move ops below
        } else {
            return $self->render_error( $c, 412 );
        }
    }

    if ( -e $dest && !$over ) {
        $self->render_error( $c, 412 );
    } else {
        if ( $over && -d $path && -f $dest ) {
            unlink( $dest );
        }
        unless( rmove( $path, $dest ) ) {
            warn "can't move $path to $dest : $!\n";
            return $self->render_error( $c, 400 );
        }
        if ( $replaced ) {
            return $c->render_text( 'No Content', status => 204 );
        } else {
            return $c->render_text( 'Created', status => 201 );
        }
    }
}

# 8.8
sub cmd_copy {
    my ( $self, $c, $path ) = @_;

    # 8.8.3
    return $self->render_error( $c, 400 ) unless my $dest = $self->_get_dest( $c );

    my $over = ( $c->req->headers->header( 'Overwrite' ) || '' ) eq 'T' ? 1 : 0;
    my $depth = $c->req->headers->header( 'Depth' );
    $depth = defined $depth && $depth == 0 ? 0 : 1;

    return $c->render_not_found unless -e $path;

    # 8.8.4
    return $c->render_error( $c, 403 ) if $path eq $dest;

    # XXX
    # A COPY of "Depth: 0" only instructs that the collection and its
    # properties but not resources identified by its internal member URIs,
    # are to be copied.
    #
    # A copy of "Depth: infinite" or undef copies the tree
    if ( $depth == 0 ) {
        return $self->render_error( $c, 409 ) if -d $dest;
        return $self->render_error( $c, 409 ) unless mkdir( $dest, 0755 );

        return $c->render_text( 'Created', status => 201 );
    }

    my $replaced = -e $dest;

    # 8.8.6
    if ( -d $dest ) {
        if ( $over ) {
            #return $c->render_text( 'No Content', 204 );
            return $self->render_error( $c, 412 ) unless rmtree( $dest, { safe => 1 } );
            # fall through to move ops below
        } else {
            return $self->render_error( $c, 409 );
        }
    }

    if ( -e $dest && !$over ) {
        # 8.8.7
        return $self->render_error( $c, 412 );
    } else {
        # XXX depth 0
#        if ( !-d $dest && !$over ) {
#            # 8.8.4
#            return $self->render_error( $c, 409 );
#        }
        unless( rcopy( $path, $dest ) ) {
            warn "can't copy $path to $dest : $!\n";
            return $self->render_error( $c, 400 );
        }
        if ( $replaced ) {
            return $c->render_text( 'No Content', status => 204 );
        } else {
            return $c->render_text( 'Created', status => 201 );
        }
    }
}

# 8.6
sub cmd_delete {
    my ( $self, $c, $path ) = @_;

    return $c->render_not_found unless -e $path;

    return $self->render_error( $c, 400 ) if $path =~ m/\.$/ || $c->req->url->fragment;

    if ( -d $path ) {
        # 8.6.2
        return $self->render_error( $c, 405 ) unless rmtree( $path, { safe => 1 } );
    } else {
        # 8.6.1
        unless ( unlink( $path ) ) {
            warn "could not unlink $path, $!\n";
            # permission denied
            return $self->render_error( $c, 403 );
        }
    }

    $c->render_text( 'Deleted', status => 204 );
}

sub cmd_options {
    my ( $self, $c ) = @_;

    my $rsh = $c->res->headers;

    $rsh->header( 'DAV' => '1,2,<http://apache.org/dav/propset/fs/1>' );
    $rsh->header( 'MS-Author-Via' => 'DAV' );
    $rsh->header( 'Allow'         => $self->allowed_methods );
    $rsh->header( 'Content-Type'  => 'httpd/unix-directory' );
    $rsh->content_length( 0 );
    $c->res->code( 200 );
    $c->res->body( '' );
    $c->rendered;
}


sub cmd_propfind {
    my ( $self, $c ) = @_;

    warn $c->req->to_string;

    my $dom = $c->req->dom;
    my $ok = 0;

    $dom->find('prop')->until(sub {
        foreach my $child ( @{ $_[0]->children } ) {
            if ( $child->namespace eq '' ) {
                # propfind_invalid2 - FAQ
                $ok = -1;
                last;
            }
            $ok = 1;
            warn "children:".$child->name."\n";
        }
        $ok != -1;
    });

    return $self->render_error( $c, 400 ) if $ok != 1;

    return $self->render_error( $c, 500 );
}

sub cmd_get {
    my ( $self, $c ) = @_;
    $c->app->static->serve( $c, $c->stash( 'dav.relpath' ) );
}

# XXX check this
*cmd_head = *cmd_get;

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

    return $c->rendered;
}

sub _get_dest {
    my ( $self, $c ) = @_;

    return unless my $dest = $c->req->headers->header( 'Destination' );

    my $dpath = Mojo::URL->new( $dest )->path->clone->canonicalize->to_string;

    # remove prefix
    if ( my $prefix = $c->stash( 'dav.prefix' ) ) {
        return unless $dpath =~ s/^$prefix//;
    }

    my $dparts = Mojo::Path->new->parse( $dpath )->parts;

    return if $dparts->[0] eq '..';

    my $dest_abs = File::Spec->catfile( $c->stash( 'dav.absroot' ), @$dparts );

    $c->stash( 'dav.dest' => $dest_abs );

    return $dest_abs;
}

1;

