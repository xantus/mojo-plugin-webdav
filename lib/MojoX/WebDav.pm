package MojoX::WebDav;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::URL;
use Mojo::Asset::File;
use File::Copy::Recursive qw( rcopy rmove );
use File::Path qw( mkpath rmtree );
use File::Spec qw();
use Mojo::ByteStream 'b';
use HTTP::Date qw();
use Date::Format qw();
use bytes;

# I feel dirty
use XML::LibXML;

__PACKAGE__->attr( [qw/ mtfnpy /] );
__PACKAGE__->attr( methods     => sub { [ qw( GET HEAD OPTIONS PROPFIND DELETE PUT COPY LOCK UNLOCK MOVE POST TRACE MKCOL ) ] } );
__PACKAGE__->attr( allowed_methods => sub { join( ',', @{ shift->methods } ) });

sub register {
    my ( $self, $app, $config ) = @_;

    $config ||= {};

    $app->plugins->add_hook( before_dispatch => sub {
        $_[1]->stash(
            'dav.root' => $config->{root} || '/',
            'dav.prefix' => $config->{prefix} || '/'
        );
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

    $c->stash( 'dav.reqpath' => "$path" );

    # remove prefix
    if ( my $prefix = $c->stash( 'dav.prefix' ) ) {
        return unless $path =~ s/^$prefix//;
        $path ||= '/';
    }

    $c->stash(
        'dav.request' => 1,
        # XXX revisit this
        'dav.absroot' => File::Spec->catdir( $c->app->static->root, $c->stash( 'dav.root' ) ),
        'dav.path'    => $path,
    );

    $c->res->headers->header( 'DAV' => '1,2,<http://apache.org/dav/propset/fs/1>' );
    $c->res->headers->header( 'MS-Author-Via' => 'DAV' );
#    $c->res->headers->header( 'Vary' => 'Accept-Encoding' );

    if ( my $litmus = $c->req->headers->header( 'X-Litmus' ) ) {
        $c->app->log->debug( 'Litmus test request: '.$litmus );
        if ( $litmus eq 'props: 4 (propfind_d0)' ) {
            warn $c->req->to_string;
        }
    }

    my $cmd = "cmd_". lc $c->req->method;

    if ( my $x = UNIVERSAL::can( $self, $cmd ) ) {
        my $parts = Mojo::Path->new->parse($path)->parts;

        return $c->render_not_found if $parts->[0] && $parts->[0] eq '..';

        my $abs_path = File::Spec->catfile( $c->stash( 'dav.absroot' ), @$parts );
        $c->stash( 'dav.rel' => File::Spec->catfile( @$parts ) || '/' );
        $c->stash( 'dav.relpath' => File::Spec->catfile( $c->stash( 'dav.root' ), @$parts ) );
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
    return $self->render_error( $c, 403 ) if $c->stash( 'dav.path' ) eq '/';

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
#    $depth = ( defined $depth && $depth =~ /^(0|1)$/ ) ? $1 : 'infinite';

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
    $depth = ( defined $depth && $depth =~ /^(0|1|infinite)$/ ) ? $1 : 'infinite';

    return $c->render_not_found unless -e $path;

    # 8.8.4
    return $c->render_error( $c, 403 ) if $path eq $dest;

    # XXX
    # A COPY of "Depth: 0" only instructs that the collection and its
    # properties but not resources identified by its internal member URIs,
    # are to be copied.
    #
    # A copy of "Depth: infinite" or undef copies the tree
    if ( $depth eq '0' ) {
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
#    $c->res->body( '' );
    $c->rendered;
}

sub cmd_propfind {
    my ( $self, $c, $abspath ) = @_;
    my $reqinfo = 'allprop';
    my @reqprops;

    if ( $c->req->headers->content_length ) {
        my $parser = eval { XML::LibXML->new->parse_string( $c->req->body ); };
        return $self->render_error( $c, 400 ) if $@;

        $reqinfo = $parser->find( '/*/*' )->shift->localname;
        if ( $reqinfo eq 'prop' ) {
            foreach my $node ( $parser->find( '/*/*/*' )->get_nodelist ) {
                push( @reqprops, [ $node->namespaceURI, $node->localname ] );
            }
        }
    }

    return $c->render_not_found unless -e $abspath;

    my $depth = $c->req->headers->header( 'Depth' );
    $depth = ( defined $depth && $depth =~ /^(0|1)$/ ) ? $1 : 'infinite';

    my $doc = XML::LibXML::Document->new( '1.0', 'utf-8' );
    my $multistat = $doc->createElement( 'D:multistatus' );
    $multistat->setAttribute( 'xmlns:D', 'DAV:' );
    $doc->setDocumentElement( $multistat );

    my @paths;
    if ( $depth eq '1' and -d $abspath ) {
        opendir( my $dir, $abspath );
        #@paths = File::Spec->no_upwards( grep { !/^\./ } readdir $dir );
        @paths = File::Spec->no_upwards( readdir $dir );
        closedir( $dir );
        push( @paths, $c->stash( 'dav.rel' ) );
    } else {
        @paths = ( $c->stash( 'dav.rel' ) );
    }

    my $root = $c->stash( 'dav.absroot' );
    foreach my $rel ( @paths ) {
        my $path = File::Spec->catdir( $root, $rel );
        my ( $size, $mtime, $ctime ) = ( stat( $path ) )[ 7, 9, 10 ];

        # modified time is stringified human readable HTTP::Date style
        $mtime = HTTP::Date::time2str($mtime);

        $ctime = Date::Format::time2str( '%Y-%m-%dT%H:%M:%S', $ctime );
        $size ||= '';

        my $resp = $doc->createElement( 'D:response' );
        $multistat->addChild( $resp );
        my $href = $doc->createElement( 'D:href' );
        my $uri = File::Spec->catdir(
            map { b( $_ )->url_escape->to_string } File::Spec->splitdir( $rel )
        );
        $uri .= '/' if -d $path && !$uri =~ m/\/$/;
        $uri = '/'.$uri unless $uri =~ m/^\//;

        $href->appendText( $uri );
        $resp->addChild( $href );

        my $okprops = $doc->createElement( 'D:prop' );
        my $badprops = $doc->createElement( 'D:prop' );
        my $prop;

        if ( $reqinfo eq 'prop' ) {
            my $prefixes = { 'DAV:' => 'D' };
            my $n = 'E';

            foreach my $reqprop ( @reqprops ) {
                my ($ns, $name) = @$reqprop;
                if ( $ns eq 'DAV:' && $name eq 'creationdate' ) {
                    $prop = $doc->createElement( 'D:creationdate' );
                    $prop->appendText( $ctime );
                    $okprops->addChild( $prop );
                } elsif ( $ns eq 'DAV:' && $name eq 'getcontentlength' ) {
                    $prop = $doc->createElement( 'D:getcontentlength' );
                    $prop->appendText( $size );
                    $okprops->addChild( $prop );
                } elsif ( $ns eq 'DAV:' && $name eq 'getcontenttype' ) {
                    $prop = $doc->createElement( 'D:getcontenttype' );
                    #$prop->appendText( 'httpd/unix-'.( -d $path ? 'directory' : 'file' ) );
                    if ( -d $path ) {
                        $prop->appendText( 'httpd/unix-directory' );
                    } else {
                        # crude
                        my ( $ext ) = $path =~ m/\.([^\.]+)$/;
                        if ( $ext ) {
                            $prop->appendText( $c->app->types->type( lc $ext ) || 'httpd/unix-file' );
                        } else {
                           $prop->appendText( 'httpd/unix-file' );
                        }
                    }
                    $okprops->addChild( $prop );
                } elsif ( $ns eq 'DAV:' && $name eq 'getlastmodified' ) {
                    $prop = $doc->createElement( 'D:getlastmodified' );
                    $prop->appendText( $mtime );
                    $okprops->addChild( $prop );
                } elsif ($ns eq 'DAV:' && $name eq 'resourcetype') {
                    $prop = $doc->createElement( 'D:resourcetype' );
                    $prop->addChild( $doc->createElement( 'D:collection' ) ) if -d $path;
                    $okprops->addChild( $prop );
                } else {
                    my $prefix = $prefixes->{ $ns };
                    unless ( defined $prefix ) {
                        $prefix = "$n";

                        # mod_dav sets <response> 'xmlns' attribute
                        #$badprops->setAttribute("xmlns:$prefix", $ns);
                        $resp->setAttribute("xmlns:$prefix", $ns);

                        $prefixes->{ $ns } = $prefix;
                        $n++;
                    }

                    $badprops->addChild( $doc->createElement( "$prefix:$name" ) );
                }
            }
        } elsif ( $reqinfo eq 'propname' ) {
            $okprops->addChild( $doc->createElement( 'D:creationdate' ) );
            $okprops->addChild( $doc->createElement( 'D:getcontentlength' ) );
            $okprops->addChild( $doc->createElement( 'D:getcontenttype' ) );
            $okprops->addChild( $doc->createElement( 'D:getlastmodified' ) );
            $okprops->addChild( $doc->createElement( 'D:resourcetype' ) );
        } else {
            $prop = $doc->createElement( 'D:creationdate' );
            $prop->appendText( $ctime );
            $okprops->addChild( $prop );

            $prop = $doc->createElement( 'D:getcontentlength' );
            $prop->appendText( $size );
            $okprops->addChild( $prop );

            $prop = $doc->createElement( 'D:getcontenttype' );
            #$prop->appendText( 'httpd/unix-'.( -d $path ? 'directory' : 'file' ) );
            if ( -d $path ) {
                $prop->appendText( 'httpd/unix-directory' );
            } else {
                # crude
                my ( $ext ) = $path =~ m/\.([^\.]+)$/;
                if ( $ext ) {
                    $prop->appendText( $c->app->types->type( lc $ext ) || 'httpd/unix-file' );
                } else {
                   $prop->appendText( 'httpd/unix-file' );
                }
            }
            $okprops->addChild( $prop );

            $prop = $doc->createElement( 'D:getlastmodified' );
            $prop->appendText( $mtime );
            $okprops->addChild( $prop );

            $prop = $doc->createElement( 'D:supportedlock' );
            foreach (qw( exclusive shared )) {
                my $scope = $doc->createElement( 'D:lockscope' );
                $scope->addChild( $doc->createElement( "D:$_" ) );
                my $lock = $doc->createElement( 'D:lockentry' );
                $lock->addChild($scope);

                my $type = $doc->createElement( 'D:locktype' );
                $type->addChild( $doc->createElement( 'D:write' ) );
                $lock->addChild( $type );

                $prop->addChild( $lock );
            }
            $okprops->addChild( $prop );

            $prop = $doc->createElement( 'D:resourcetype' );
            if ( -d $path ) {
                my $col = $doc->createElement( 'D:collection' );
                $prop->addChild( $col );
            }
            $okprops->addChild( $prop );
        }

        if ( $okprops->hasChildNodes ) {
            my $propstat = $doc->createElement( 'D:propstat' );
            $propstat->addChild( $okprops );
            my $stat = $doc->createElement( 'D:status' );
            $stat->appendText( 'HTTP/1.1 200 OK' );
            $propstat->addChild( $stat );
            $resp->addChild( $propstat );
        }

        if ( $badprops->hasChildNodes ) {
            my $propstat = $doc->createElement( 'D:propstat' );
            $propstat->addChild( $badprops );
            my $stat = $doc->createElement( 'D:status' );
            $stat->appendText( 'HTTP/1.1 404 Not Found' );
            $propstat->addChild( $stat );
            $resp->addChild( $propstat );
        }
    }

    my $xml = $doc->toString(1);
    warn $xml;
    $c->render_text( $xml, status => 207, format => 'xml' );
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

    return if ( $res->code || '' ) eq $code;

    $c->render_text(qq|
<!doctype html><html>
    <head><title>Error $code</title></head>
    <body><h2>Error $code</h2></body>
</html>
|, status => $code, type => 'html' );
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
