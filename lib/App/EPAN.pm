package App::EPAN;

# ABSTRACT: Exclusive Perl Archive Nook

use strict;
use warnings;
use English qw( -no_match_vars );
use 5.012;
use version;
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
use IPC::Run   ();
use File::Copy ();
use File::Which qw< which >;

has configuration => (
   is        => 'rw',
   lazy      => 1,
   predicate => 'has_config',
   clearer   => 'clear_config',
   default   => sub { {} },
);
has action     => (is => 'rw',);
has last_index => (is => 'rw',);

sub run {
   my $package = shift;
   my $self    = $package->new();
   $self->get_options(@_);

   my $action = $self->action();
   if (!defined $action) {
      LOGDIE "no action";
   }
   if (my $method = $self->can("action_$action")) {
      $self->$method();
   }
   else {
      LOGDIE "action $action is not supported";
   }
   return;
} ## end sub run

sub get_options {
   my $self = shift;
   my $action =
     (scalar(@_) && length($_[0]) && (substr($_[0], 0, 1) ne '-'))
     ? shift(@_)
     : 'no-action';
   local @ARGV = @_;
   $self->action($action);
   my %config = ();
   GetOptions(
      \%config,
      qw(
        mailrc|m|1=s
        output|packages-details|o|2=s
        modlist|modlist-data|l|3=s
        target|t=s
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
   $self->configuration(
      {
         cmdline_config => \%config,
         config         => \%config,
         args           => [@ARGV],
      }
   );
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
} ## end sub action_index

sub _save {
   my ($self, $name, $contents, $config_key, $output) = @_;

   if (defined(my $confout = $self->config($config_key))) {
      $output =
          !length($confout) ? undef
        : $confout eq '-'   ? \*STDOUT
        :                     file($confout);
   } ## end if (defined(my $confout...))
   if (defined $output) {
      INFO "saving output to $output";
      $self->save($output,
         scalar(ref($contents) ? $contents->() : $contents));
   }
   else {
      INFO "empty filename for $name file, skipping";
   }
} ## end sub _save

sub do_index {
   my ($self, $basedir) = @_;

   $self->_save(
      '01mailrc',    # name
      '',
      'mailrc',      # configuration key to look output file
      $basedir->file(qw< authors 01mailrc.txt.gz >)    # default
   );

   $self->_save(
      '02packages.details',    # name
      sub {                    # where to get data from. Call is avoided if
                               # no file on output
         INFO "getting contributions for regenerated index...";
         $self->index_for($basedir);
      },
      'output',                # configuration key to look output file
      $basedir->file(qw< modules 02packages.details.txt.gz >)    # default
   );

   $self->_save(
      '03modlist.data',                                          # name
      <<'END_OF_03_MODLIST_DATA',
File:        03modlist.data
Description: These are the data that are published in the module
        list, but they may be more recent than the latest posted
        modulelist. Over time we'll make sure that these data
        can be used to print the whole part two of the
        modulelist. Currently this is not the case.
Modcount:    0
Written-By:  PAUSE version 1.005
Date:        Sun, 28 Jul 2013 07:41:15 GMT

package CPAN::Modulelist;
# Usage: print Data::Dumper->new([CPAN::Modulelist->data])->Dump or similar
# cannot 'use strict', because we normally run under Safe
# use strict;
sub data {
   my $result = {};
   my $primary = "modid";
   for (@$CPAN::Modulelist::data){
      my %hash;
      @hash{@$CPAN::Modulelist::cols} = @$_;
      $result->{$hash{$primary}} = \%hash;
   }
   return $result;
}
$CPAN::Modulelist::cols = [ ];
$CPAN::Modulelist::data = [ ];
END_OF_03_MODLIST_DATA
      'modlist',    # configuration key to look output file
      $basedir->file(qw< modules 03modlist.data.gz >)    # default
   );
} ## end sub do_index

sub save {
   my ($self, $path, $contents) = @_;
   my ($fh, $is_gz);
   if (ref($path) eq 'GLOB') {
      $fh    = $path;
      $is_gz = 0;
   }
   else {
      $path->dir()->mkpath() unless -d $path->dir()->stringify();
      $fh    = $path->open('>');
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
   my @index = $self->index_body_for($path);
   our $VERSION ||= 'whateva';
   my $header = <<"END_OF_HEADER";
File:         02packages.details.txt
URL:          http://cpan.perl.org/modules/02packages.details.txt.gz
Description:  Package names found in directory \$CPAN/authors/id/
Columns:      package name, version, path
Intended-For: Automated fetch routines, namespace documentation.
Written-By:   epan $VERSION
Line-Count:   ${ \ scalar @index }
Last-Updated: ${ \ scalar localtime() }
END_OF_HEADER
   return join "\n", $header, @index, '';
} ## end sub index_for

sub collect_index_for {
   my ($self, $path) = @_;
   $path = dir($path);
   my $idpath = $path->subdir(qw< authors id >);
   my %data_for;
   for my $file (File::Find::Rule->extras({follow => 1})->file()
      ->in($idpath->stringify()))
   {
      INFO "indexing $file";
      my $index_path =
        file($file)->relative($idpath)->as_foreign('Unix')->stringify();
      my $dm = Dist::Metadata->new(file => $file);
      my $version_for = $dm->package_versions();

      $data_for{distro}{$index_path} = $version_for;
      (my $bare_index_path = $index_path) =~
        s{^(.)/(\1.)/(\2.*?)/}{$3/}mxs;
      $data_for{bare_distro}{$bare_index_path} = $version_for;

      my %_localdata_for;
      my $score = 0;
      while (my ($module, $version) = each %$version_for) {
         my $print_version = $version // 'undef';
         DEBUG "data for $module: [$print_version] [$index_path]";
         $_localdata_for{$module} = {
            version => $version,
            distro  => $index_path,
         };
         $score++;
         next unless exists($data_for{module}{$module});
         DEBUG 'some previous version exists';
         if (! defined $version) {
            $score--;
            $score-- if defined($data_for{module}{$module}{version});
         }
         elsif (defined $data_for{module}{$module}{version}) {
            my $tv = version->parse($version);
            my $pv = version->parse($data_for{module}{$module}{version});
            $score-- if $pv > $tv;
         }
      } ## end while (my ($module, $version...))

      next unless $score; # no score, not the most recent
      DEBUG 'getting this version';

      # copy stuff over to the "official" data for modules
      $data_for{module}{$_} = $_localdata_for{$_} for keys %_localdata_for;
   } ## end for my $file (File::Find::Rule...)
   $self->last_index(\%data_for);
   return %data_for if wantarray();
   return \%data_for;
} ## end sub collect_index_for

sub index_body_for {
   my ($self, $path) = @_;

   my $data_for        = $self->collect_index_for($path);
   my $module_data_for = $data_for->{module};
   my @retval;
   for my $module (sort keys %{$module_data_for}) {
      my $md         = $module_data_for->{$module};
      my $version    = $md->{version} || 'undef';
      my $index_path = $md->{distro};
      my $fw         = 38 - length $version;
      $fw = length $module if $fw < length $module;
      push @retval, sprintf "%-${fw}s %s  %s", $module, $version,
        $index_path;
   } ## end for my $module (sort keys...)
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
} ## end sub action_create

sub action_update {
   my ($self) = @_;

   my $target = dir($self->config('target') // 'epan');
   $target->mkpath() unless -d $target;

   my $dists   = $target->stringify();
   my $local   = $target->subdir('local')->stringify();
   my @command = (
      qw< cpanm --reinstall --quiet --self-contained >,
      '--local-lib-contained' => $local,
      '--save-dists'          => $dists,
      $self->args(),
   );

   my ($out, $err);
   {
      local $SIG{TERM} = sub {
         WARN "cpanm: received TERM signal, ignoring";
      };
      INFO "calling @command";
      IPC::Run::run \@command, \undef, \*STDOUT, \*STDERR
        or LOGDIE "cpanm: $? ($err)";
   }

   INFO 'onboarding completed, indexing...';
   $self->do_index($target);
   my $data_for = $self->last_index();

   INFO 'saving distlist';
   my @distros = $self->last_distlist();
   $self->save($target->file('distlist.txt'), join "\n", @distros, '');

   INFO 'saving modlist';
   my @modules = $self->last_modlist();
   $self->save($target->file('modlist.txt'), join "\n", @modules, '');

   my $file = $target->file('install.sh');
   if (!-e $file) {
      $self->save($file, <<'END_OF_INSTALL');
#!/bin/bash
ME=$(readlink -f "$0")
MYDIR=$(dirname "$ME")

TARGET="$MYDIR/local"
[ $# -gt 0 ] && TARGET=$1

if [ -n "$TARGET" ]; then
   "$MYDIR/cpanm" --mirror "file://$MYDIR" --mirror-only \
      -L "$TARGET" \
      $(<"$MYDIR/modlist.txt")
else
   "$MYDIR/cpanm" --mirror "file://$MYDIR" --mirror-only \
      $(<"$MYDIR/modlist.txt")
fi
END_OF_INSTALL
      chmod 0777 & ~umask(), $file->stringify();
   } ## end if (!-e $file)

   $file = $target->file('cpanm');
   if (!-e $file) {
      my $cpanm = which('cpanm');
      File::Copy::copy($cpanm, $file->stringify());
      chmod 0777 & ~umask(), $file->stringify();
   }
} ## end sub action_update

{
   no strict 'subs';
   *action_install = \&action_update;
   *action_add     = \&action_update;
}

sub last_distlist {
   my ($self) = @_;
   return keys %{$self->last_index()->{bare_distro}};
}

sub last_modlist {
   my ($self) = @_;
   my @retval =
     map { (sort keys %$_)[0] }
     values %{$self->last_index()->{bare_distro}};
} ## end sub last_modlist

1;
__END__
