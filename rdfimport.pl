#!/usr/bin/perl

use strict;
no strict 'subs';
use warnings;

=head1 NAME

rdfimport - Import RDF data into some Triple store

=cut

use RDF::Trine qw(0.133 statement iri literal);
use RDF::Trine::Parser;
use RDF::Trine::Serializer;
use RDF::Trine::Namespace;
use Pod::Usage;
use Getopt::Long;
use RDF::Trine::Namespace qw(rdf xsd);

our $VERSION = '0.1.3';

=head1 USAGE

rdfimport [ options ] [ source-files-and-urls... ]

    Options:
       -store CONFIG    store configuration string
       -base URI        base URI when importing from files
       -input FORMAT    force a specific input format (rdfxml,turtle etc.)
       -output FORMAT   serialize the full store as FORMAT after import
       -config FILE     read configuration from file FILE
       -flush           flush store before importing triples
       -void            add VoID statements, dump model (if enabled)
       -help            brief help message
       -man             full documentation
       -quiet           suppress status messages

=head2 C<< -store >>

The store must be specified as L<RDF::Trine::Store> configuration string.
By default an in-memory store (C<Memory>) is used and destroyed after import.
Some examples of possible configuration strings:
 
  DBI;mymodel;DBI:mysql:database=rdf;user;password
  DBI;;DBI:SQLite:database.sqlite
  SPARQL;http://example/

=head2 C<< -config >>

The store and the base URI can also be read from a configuration file.
This file must be a Turtle RDF file like the following:

  @prefix : <#> .
  <>  :base <http://example.org/> ;
      :store "DBI;;DBI:SQLite:mydb.sqlite" .

=head2 C<< -input >> and C<< -output >>

The supported RDF serialization formats include C<rdfxml>, C<turtle>,
C<rdfjson>, C<ntriples>, and C<nquads>. Parsing in addition is possible
in C<trig> and C<rdfa> (not tested yet). See L<RDF::Trine> for details.

=head2 C<< -void >>

Add statements from the Vocabulary of Interlinked Datasets (VoID) and
possibly dumps the whole model into a file (in Turtle syntax). You must
enable dumping in the config file or in the input file, for instance:

  <>
    void:dataDump "foo.ttl" . # dumps model to foo.ttl

=cut
  
my ($o_help,$o_man,$o_quiet,$o_config,$o_void,
    $o_input,$o_base,$o_store,$o_output,$o_flush);
GetOptions(
    'store:s'  => \$o_store,
    'base:s'   => \$o_base,
    'input:s'  => \$o_input,
    'output:s' => \$o_output,
    'config:s' => \$o_config,
    'flush'    => \$o_flush,
    'void'     => \$o_void,
    'help|?'   => \$o_help,
    'man'      => \$o_man,
    'quiet'    => \$o_quiet,
) or pod2usage(2);
pod2usage("pdfimport $VERSION") if ($o_help);
pod2usage(-verbose => 2) if ($o_man);
unless (@ARGV) {
    print STDERR "please specify an input file/URL or -h for help!\n";
    exit 1;
}

my $config = RDF::Trine::Model->new;
if ($o_config) {
    my $parser = RDF::Trine::Parser->new( 'turtle' );
    print "read config file $o_config\n" unless $o_quiet;
    my $cns = RDF::Trine::Namespace->new("file://$o_config");
    $parser->parse_file_into_model( $cns->uri, $o_config, $config );

    unless ($o_base) {
        my ($c_base) = $config->objects( $cns->uri, $cns->uri('#base'), type => 'resource' );
        $o_base = $c_base->uri_value if $c_base;
    }
    unless ($o_store) {
        my ($c_store) = $config->objects( $cns->uri, $cns->uri('#store'), type => 'literal' );
        $o_store = $c_store->literal_value if $c_store;
    }
}

$o_store = 'Memory' unless $o_store;
my $model = RDF::Trine::Model->new( RDF::Trine::Store->new( $o_store ) );
my $parser = 'RDF::Trine::Parser';
$parser = RDF::Trine::Parser->new( $o_input ) if $o_input;

my $serializer;
if ($o_output) {
    $o_quiet = 1;
    $serializer = RDF::Trine::Serializer->new( $o_output );
}

if ($o_flush) {
    print "flush store $o_store\n" unless $o_output;
    $model->remove_statements( undef, undef, undef );
}

my $base;
my $size_before = $model->size;
foreach my $from (@ARGV) {
    print "import $from ... " unless $o_quiet;
    eval {
        if ( $from =~ /^http[s]?:\/\// ) {
            $base = $o_base || $from;
            $parser->parse_url_into_model( $from, $model );
        } else {
            $base = $o_base || "file://$from";
            $parser->parse_file_into_model( $base, $from, $model );
        }
    };
    if ($@) {
        print "failed:\n" unless $o_quiet;
        print STDERR "$@\n";
        exit;
    } elsif( not $o_quiet) {
        print "ok\n";
    }
}

my $growth = $model->size - $size_before;
print "imported $growth additional triples\n" unless $o_quiet;

my $void = RDF::Trine::Namespace->new("http://rdfs.org/ns/void#");

if ( $o_void ) {
    my ($dump) = $config->objects( $base, $void->dataDump, type => 'literal_value' );
    my $dataset = iri($base);
    my @statements = ( 
        statement( $dataset, $rdf->type, $void->Dataset ),
    );

    push @statements, statement( $dataset, $void->dataDump, literal($dump) ) if $dump;

    # TODO: automatically add void statements, e.g. void:vocabulary (?)
    # TODO: copy void statements from the config file (?)

    $model->add_statement( $_ ) for @statements;

    my $size = $model->size + 1;
    $model->remove_statements( $dataset, $void->triples, undef );
    $model->add_statement( statement( 
        $dataset, $void->triples, literal( $size, undef, $xsd->integer ) ) );

    if ( $dump ) {
        print "writing dump file $dump with $size triples\n" unless $o_quiet;
        if ( open my $fh, ">$dump" ) {
            # TODO: add namespaces to abbreviate syntax
            RDF::Trine::Serializer->new('turtle')->
                serialize_model_to_file ( $fh, $model );
        } else {
            print STDERR "failed to write file\n";
        }
    }
}

$serializer->serialize_model_to_file ( *STDOUT, $model )
    if ( $serializer );

=head1 DESCRIPTION

This script is intended to import RDF data from files or LinkedData URIs
into triple stores.

=cut

