package App::EPAN;

# ABSTRACT: Exclusive Perl Archive Nook

use strict;
use warnings;
use English qw( -no_match_vars );
use 5.012;
use autodie;
use Getopt::Long qw< :config gnu_getopt >;
use Pod::Usage qw< pod2usage >;
use Dist::Metadata ();
use Path::Class qw< file dir >;
use Cwd qw< cwd >;
use File::Find::Rule ();
use Compress::Zlib   ();
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
use Moo;
use IPC::Run ();

has configuration => (
   is        => 'rw',
   lazy      => 1,
   predicate => 'has_config',
   clearer   => 'clear_config',
   default   => sub { {} },
);
has action => (
   is => 'rw',
);
has last_index => (
   is => 'rw',
);

sub run {
   my $package = shift;
   my $self = $package->new();
   $self->get_options(@_);

   my $action = $self->action();
   if (! defined $action) {
      LOGDIE "no action";
   }
   if (my $method = $self->can("action_$action")) {
      $self->$method();
   }
   else {
      LOGDIE "action $action is not supported";
   }
   return;
}

sub get_options {
   (my $self, my $action, local @ARGV) = @_;
   $self->action($action);
   my %config = ();
   GetOptions(
      \%config,
      qw(
        output|o=s
        usage! help! man! version!
        )
   ) or pod2usage(-verbose => 99, -sections => 'USAGE');
   our $VERSION ||= 'whateva';
   pod2usage(message => "$0 $VERSION", -verbose => 99, -sections => ' ')
     if $config{version};
   pod2usage(-verbose => 99, -sections => 'USAGE') if $config{usage};
   pod2usage(-verbose => 99, -sections => 'USAGE|EXAMPLES|OPTIONS')
     if $config{help};
   pod2usage(-verbose => 2) if $config{man};
   $self->configuration({
      cmdline_config => \%config,
      config => \%config,
      args => [ @ARGV ],
   });
   return;
} ## end sub get_options

sub args {
   return @{$_[0]->configuration()->{args}};
}

sub config {
   my $self = shift;
   return @{$self->configuration()->{config}}{@_} if wantarray();
   return $self->configuration()->{config}{shift @_};
}

sub action_index {
   my ($self) = @_;

   my $basedir = dir(($self->args())[0] || cwd());
   return $self->do_index($basedir);
}

sub do_index {
   my ($self, $basedir) = @_;

   INFO "getting contributions for regenerated index...";
   my $index_contents = $self->index_for($basedir);

   my $output = $basedir->file(qw< modules 02packages.details.txt.gz >);
   if (defined(my $confout = $self->config('output'))) {
      $output = $confout eq '-' ? \*STDOUT : file($confout);
   }

   INFO "saving output to $output";
   $self->save($output, $index_contents);
}

sub save {
   my ($self, $path, $contents) = @_;
   my ($fh, $is_gz);
   if (ref($path) eq 'GLOB') {
      $fh    = $path;
      $is_gz = 0;
   }
   else {
      $path->dir()->mkpath() unless -d $path->dir()->stringify();
      $fh = $path->open('>');
      $is_gz = $path->stringify() =~ m{\.gz$}mxs;
   }

   if ($is_gz) {
      my $gz = Compress::Zlib::gzopen($fh, 'wb');
      $gz->gzwrite($contents);
      $gz->gzclose();
   }
   else {
      binmode $fh;
      print {$fh} $contents;
   }
   return;
} ## end sub save

sub index_for {
   my ($self, $path) = @_;
   my @index  = $self->index_body_for($path);
   our $VERSION ||= 'whateva';
   my $header = <<"END_OF_HEADER";
File:         02packages.details.txt
URL:          http://cpan.perl.org/modules/02packages.details.txt.gz
Description:  Package names found in directory \$CPAN/authors/id/
Columns:      package name, version, path
Intended-For: Automated fetch routines, namespace documentation.
Written-By:   mcpan-reindex $VERSION
Line-Count:   ${ \ scalar @index }
Last-Updated: ${ \ scalar localtime() }
END_OF_HEADER
   $self->last_index({header => $header, index => \@index});
   return join "\n", $header, @index, '';
} ## end sub index_for

sub index_body_for {
   my ($self, $path, $idpath) = @_;

   my @retval;
   if (-d $path) {    # directory...
      my $basedir = dir($path);
      $idpath = $basedir->subdir(qw< authors id >);
      for my $path (File::Find::Rule->file()->in($idpath->stringify())) {
         INFO "indexing $path";
         push @retval, $self->index_body_for($path, $idpath);
      }
      @retval = sort @retval;
   } ## end if (-d $path)
   else {             # it's a file...
      my $index_path =
        file($path)->relative($idpath)->as_foreign('Unix')->stringify();
      my $dm = Dist::Metadata->new(file => $path);
      my $version_for = $dm->package_versions();
      for my $module (sort keys %$version_for) {
         my $version = $version_for->{$module} || 'undef';
         my $fw = 38 - length $version;
         $fw = length $module if $fw < length $module;
         push @retval, sprintf "%-${fw}s %s  %s", $module, $version,
           $index_path;
      } ## end for my $module (sort keys...
   } ## end else [ if (-d $path)
   return @retval if wantarray();
   return \@retval;
} ## end sub index_body_for

sub action_create {
   my ($self) = @_;

   my $target = dir($self->config('target') // 'epan');
   LOGDIE "target directory $target exists, use update instead"
      if -d $target;
   $target->mkpath();

   return $self->action_update();
}

sub action_update {
   my ($self) = @_;

   my $target = dir($self->config('target') // 'epan');
   $target->mkpath() unless -d $target;

   my @command = (
      qw< cpanm -L /xxx --scandeps --format dists --save-dists >,
      $target->stringify(),
      $self->args(),
   );
   my ($out, $err);
   IPC::Run::run \@command, \undef, \$out, \*STDERR
      or LOGDIE "cpanm: $? ($err)";

   $self->save($target->file('distlist.txt'), $out);

   $self->do_index($target);

   my $modlist = $self->modlist_for($out);
   $self->save($target->file('modlist.txt'), $modlist);
   
}

sub modlist_for {
   my ($self, $list) = @_;
   my @list = my @order = split /\n/, $list;
   my %module_for;
   for my $line (@{$self->last_index()->{index}}) {
      last unless @list;
      for my $i (0 .. $#list) {
         next unless $line =~ m{$list[$i]$};
         ($module_for{$list[$i]} = $line) =~ s{\s.*}{}mxs;
         splice @list, $i, 1;
         last;
      }
   }
   return join "\n", @module_for{@order}, '';
}


1;
__END__

=head1 NAME

mcpan-reindex - regenerated index of a [Mini-]CPAN tree

=head1 VERSION

Ask the version number to the script itself, calling:

   shell$ mcpan-reindex --version


=head1 USAGE

   mcpan-reindex [--usage] [--help] [--man] [--version]

   mcpan-reindex [--output|-o filename] [dirname]

=head1 EXAMPLES

   # regenerated index in ./modules/02packages.details.txt.gz, assuming
   # to be in root directory of CPAN tree
   shell$ mcpan-reindex

   # prints index on standard output, works on /path/to/minicpan
   shell$ mcpan-reindex -o - /path/to/minicpan


=head1 DESCRIPTION

This program regenerates the index in a tree that is (mostly) compliant
with how CPAN is organized (which is what most tools expect). In particular,
it regenerates the file F<modules/02package.details.txt.gz>, used by these
tools to see where to get the files related to a module.

This can be useful when you have a starting base - compound of modules
coming from CPAN and your own distribution - already arranged in the
right shape, but you need to generate an index. For example, this happens
when you collect some distribution files using L<cpanminus>:

   shell$ cpanminus -L /xxx --scandeps --save-dists dists Mod1 Mod2...

because it saves the needed distributions in C<dists> but it does not
generate the index. So, if you want to prepare a pack of modules to carry
with your application, you can do like this:

   $ figure_out_modules > modlist
   $ cpanm -L /xxx --scandeps --save-dists dists $(<modlist)
   $ mcpan-reindex dists
   $ tar cvf dists.tar dists

then carry dists.tar with you, at which point you can:

   $ cpanm --mirror file://$YOURPATH --mirror-only Mod1 Mod2 ...

=head1 OPTIONS

You can simply call the program, which means the following:

=over

=item *

the current working directory (see L<Cwd>) is the root of your CPAN-like
tree

=item *

the F<02packages.details.txt.gz> file will be saved into
F<modules/02packages.details.txt.gz> under the current directory.

=back

If you want, you can provide the path to the root of your CPAN-like tree
as a straight command-line option:

   $ mcpan-reindex /path/to/your/cpan

Apart from this, the following options are supported:

=over

=item --help

print a somewhat more verbose help, showing usage, this description of
the options and some examples from the synopsis.

=item --man

print out the full documentation for the script.

=item --output | -o filename

specify where to send the output index. If you set C<->, then it will be
sent to standard output. Otherwise, the provided C<filename> will be
considered - well - a filename; depending on how it ends (i.e. with
C<.gz> or not) it will be saved as a gzipped file or as plaintext.

By default it is set to F<modules/02packages.details.txt.gz> under
the directory specified as the root of your CPAN-like tree.

=item --usage

print a concise usage line and exit.

=item --version

print the version of the script.

=back

=head1 CONFIGURATION AND ENVIRONMENT

mcpan-reindex requires no configuration files or environment variables.


=head1 DEPENDENCIES

Runs on perl 5.012, adapt it if you want to run on something older :-)

The following non-core modules are used:

=over

=item *

B<< Dist::Metadata >>

=item *

B<< Path::Class >>

=item *

B<< File::Find::Rule >>

=item *

B<< Log::Log4perl::Tiny >>

=back

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests through http://rt.cpan.org/


=head1 AUTHOR

Flavio Poletti C<polettix@cpan.org>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011, Flavio Poletti C<polettix@cpan.org>. All rights reserved.

This script is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>
and L<perlgpl>.

Questo script è software libero: potete ridistribuirlo e/o
modificarlo negli stessi termini di Perl stesso. Vedete anche
L<perlartistic> e L<perlgpl>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=head1 NEGAZIONE DELLA GARANZIA

Poiché questo software viene dato con una licenza gratuita, non
c'è alcuna garanzia associata ad esso, ai fini e per quanto permesso
dalle leggi applicabili. A meno di quanto possa essere specificato
altrove, il proprietario e detentore del copyright fornisce questo
software "così com'è" senza garanzia di alcun tipo, sia essa espressa
o implicita, includendo fra l'altro (senza però limitarsi a questo)
eventuali garanzie implicite di commerciabilità e adeguatezza per
uno scopo particolare. L'intero rischio riguardo alla qualità ed
alle prestazioni di questo software rimane a voi. Se il software
dovesse dimostrarsi difettoso, vi assumete tutte le responsabilità
ed i costi per tutti i necessari servizi, riparazioni o correzioni.

In nessun caso, a meno che ciò non sia richiesto dalle leggi vigenti
o sia regolato da un accordo scritto, alcuno dei detentori del diritto
di copyright, o qualunque altra parte che possa modificare, o redistribuire
questo software così come consentito dalla licenza di cui sopra, potrà
essere considerato responsabile nei vostri confronti per danni, ivi
inclusi danni generali, speciali, incidentali o conseguenziali, derivanti
dall'utilizzo o dall'incapacità di utilizzo di questo software. Ciò
include, a puro titolo di esempio e senza limitarsi ad essi, la perdita
di dati, l'alterazione involontaria o indesiderata di dati, le perdite
sostenute da voi o da terze parti o un fallimento del software ad
operare con un qualsivoglia altro software. Tale negazione di garanzia
rimane in essere anche se i dententori del copyright, o qualsiasi altra
parte, è stata avvisata della possibilità di tali danneggiamenti.

Se decidete di utilizzare questo software, lo fate a vostro rischio
e pericolo. Se pensate che i termini di questa negazione di garanzia
non si confacciano alle vostre esigenze, o al vostro modo di
considerare un software, o ancora al modo in cui avete sempre trattato
software di terze parti, non usatelo. Se lo usate, accettate espressamente
questa negazione di garanzia e la piena responsabilità per qualsiasi
tipo di danno, di qualsiasi natura, possa derivarne.

=cut
