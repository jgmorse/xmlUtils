#!/usr/bin/perl -w
# $Id: xml_split,v 1.5 2005/02/10 11:45:07 mrodrigu Exp $
use strict;

use XML::Twig;
use FindBin qw( $RealBin $RealScript);
use Getopt::Std;

$Getopt::Std::STANDARD_HELP_VERSION=1; # to stop processing after --help or --version

use vars qw( $VERSION $USAGE);

$VERSION= "0.02";
$USAGE= "xml_split [-l <level> | -c <cond>] [-b <base>] [-n <nb>] [-e <ext>] [-d] [-v] [-h] [-m] [-V] <files>\n";

{ # main block

my $opt={};
getopts('l:c:b:n:e:dvhmV', $opt);

# defaults
$opt->{n} ||= 2; # number of digits used for creating parts

if( $opt->{h}) { die $USAGE, "\n";            }
if( $opt->{m}) { exec "pod2text $RealBin/$RealScript"; }
if( $opt->{V}) { print "xml_split version $VERSION\n"; exit; }

if( $opt->{c}) { die "cannot use --level and --condition at the same time\n" if( $opt->{l}); }
else           { $opt->{l} ||= 1; $opt->{c}= "level( $opt->{l})"; }

my $options= { cond => $opt->{c}, base => $opt->{b}, nb_digits => $opt->{n}, ext => $opt->{e}, verbose => $opt->{v}, no_pi => $opt->{d} };

my $state;
$state->{seq_nb}=0;

if( !@ARGV)
  { $options->{base} ||= 'out';
    $options->{ext}  ||= '.xml';
    my $twig_options= twig_options( $options);
    my $t= XML::Twig->new( %$twig_options);
    $t->parse( \*STDIN);
    end_file( $t, $options, $state);
  }
else
  { foreach my $file (@ARGV)
      { 
        unless( $options->{base})
          { $state->{seq_nb}=0; }
        my( $base, $ext)= ($file=~ m{^(.*?)(\.\w+)?$});
        $options->{base} ||= $base;
        $options->{ext}  ||= $ext || '.xml';
        my $twig_options= twig_options( $options, $state);
        my $t= XML::Twig->new( %$twig_options);
        $t->parsefile( $file);
        end_file( $t, $options, $state);
      }
  }

}    

sub twig_options
  { my( $tool_options, $state)= @_;

		# base options, ensures maximun fidelity to the original document
    my $twig_options= { keep_encoding => 1, keep_spaces => 1 };

		# prepare output to the main document
		unless( $tool_options->{no_pi})
		  { my $file_name= file_name( $tool_options, { %$state, seq_nb  => 0} ); # main file name
				warn "generating main file $file_name\n" if( $tool_options->{verbose});
				open( my $out, '>', $file_name) or die "cannot create main file '$file_name': $!";
				$state->{out}= $out;
				$twig_options->{twig_print_outside_roots}= $out;
				$twig_options->{start_tag_handlers}= { $tool_options->{cond} => sub { $_->set_att( '#in_fragment' => 1); }  };
		  }
		
    $twig_options->{twig_roots}= { $tool_options->{cond} => sub { dump_elt( @_, $tool_options, $state); } };
    return $twig_options;
  }

sub dump_elt
  { my( $t, $elt, $options, $state)= @_;
    $state->{seq_nb}++;

    my $file_name= file_name( $options, $state);
    warn "generating $file_name\n" if( $options->{verbose});

    my $fragment= XML::Twig->new();
    $fragment->{twig_xmldecl} = $t->{twig_xmldecl};
    $fragment->{twig_doctype} = $t->{twig_doctype};
    $fragment->{twig_dtd}     = $t->{twig_dtd};
   
    if( !$options->{no_pis})
      { # if we are still witin a fragment, just replace the element by the PI
				# otherwise print it to the main document
				my $subdocs= $elt->att( '#has_subdocs') || 0;
				my $pi=	XML::Twig::Elt->new( '#PI')
                              ->set_pi( merge => " subdocs = $subdocs :$file_name");
															
				$elt->del_att( '#in_fragment');
				
				if( $elt->inherited_att( '#in_fragment'))
				  { $elt->parent( '*[@#in_fragment="1"]')->set_att( '#has_subdocs' => 1);
						$pi->replace( $elt);
					}
				else
				  { $elt->cut;
						$pi->print( $state->{out});
				  }
      }
		else
		  { $elt->cut; }
			
    $fragment->set_root( $elt);
    open( my $out, '>', $file_name) or die "cannot create output file '$file_name': $!";
    $fragment->print( $out);
    close $out;
  }
  
sub end_file
  { my( $t, $options, $state)= @_;
    unless( $options->{no_pi})
      { close $state->{out}; }
  }  
  
sub file_name
  { my( $options, $state)= @_;
    my $nb= sprintf( "%0$options->{nb_digits}d", $state->{seq_nb});
    my $file_name= "$options->{base}-$nb$options->{ext}";
    return $file_name;
  }

 
# for Getop::Std
sub HELP_MESSAGE    { return $USAGE;   }
sub VERSION_MESSAGE { return $VERSION; } 

__END__

=head1 NAME

  xml_split - cut a big XML file into smaller chunks

=head1 DESCRIPTION

C<xml_split> takes a (presumably big) XML file and split it in several smaller
files. The memory used is the memory needed for the biggest chunk (ie memory
is reused for each new chunk).

It can split at a given level in the tree (the default, splits children of the
root), or on a condition (using the subset
of XPath understood by XML::Twig, so C<section> or C</doc/section>).

Each generated file is replaced by a processing instruction that will allow 
C<xml_merge> to rebuild the original document. The processing instruction
format is C<< <?merge subdocs=[01] :<filename> ?> >>

File names are <file>-<nb>.xml, with <file>-00.xml holding the main document. 

=head1 OPTIONS

=over 4

=item -l <level>    

level to cut at: 1 generates a file for each child of the root, 2 for each grand
child

defaults to 1

=item -c <condition>

generate a file for each element that passes the condition

xml_split -c <section> will put each C<section> element in its own file (nested
sections are handled too)

=item -b <name>

base name for the output, files will be named <base>-<nb><.ext>

<nb> is a sequence number, see below C<--nb_digits>
<ext> is an extension, see below C<--extension>

defaults to the original file name (if available) or C<out> (if input comes 
from the standard input)

=item -n <nb>

number of digits in the sequence number for each file

if more digits than <nb> are needed, then they are used: if C<--nb_digits 2> is used
and 112 files are generated they will be named C<< <file>-01.xml >> to C<< <file>-112.xml >>

defaults to 2

=item -e <ext>

extension to use for generated files

defaults to the original file extension or C<.xml>

=item -v

verbose output

=item -V

outputs version and exit

=item -h

short help

=item -m

man (requires pod2text to be in the path)

=back

=head1 EXAMPLES

  xml_split foo.xml             # split at level 1
  xml_split -l 2 foo.xml        # split at level 2
  xml_split -c section foo.xml  # a file is generated for each section element
                                # nested sections are split properly

=head1 SEE ALSO

XML::Twig, xml_merge

=head1 TODO

=over 4

=item test

At the moment this is really alpha code, tested only on small, simple 
documents.

It would be a good idea to first check that indeed the whole document is not
loaded in memory!

=item optimize the code

any idea welcome! I have already implemented most of what I thought would 
improve performances.

=item provide other methods that PIs to keep merge information

XInclude is a good candidate.

using entities, which would seem the natural way to do it,
doesn't work, as they make it impossible to have both the main document
and the sub docs to be well-formed if the sub docs include sub-sub docs (you 
cant have entity declarations in an entity)

=back

=head1 AUTHOR

Michel Rodriguez <mirod@cpan.org>

=head1 LICENSE

This tool is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


