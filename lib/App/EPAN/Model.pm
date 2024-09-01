package App::EPAN::Model;
use v5.24;
use Moo;
use experimental qw< signatures >;
use Path::Tiny;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
use File::Find::Rule ();
use File::Copy ();
use Dist::Metadata ();
use File::Which qw< which >;
use IPC::Run;
use version;

sub __t ($path) { path($path) }
use namespace::clean;

has author           => (is => 'lazy');
has generate_helpers => (is => 'ro', default => 1);
has execute_tests    => (is => 'rw', default => 0);
has target           => (is => 'ro', default => 'epan', coerce => \&__t);
has etarget          => (is => 'lazy', init_arg => undef);
has mailrc           => (is => 'lazy');
has packages_details => (is => 'lazy');
has modlist_data     => (is => 'lazy');
has last_index       => (is => 'rw');

sub _build_etarget ($self) {
   my $target = $self->target;
   $target->mkpath unless -d $target;
   return $target;
}

sub _build_author ($self) { return 'LOCAL' }

sub _build_mailrc ($self) {
   return $self->target->child(qw< authors 01mailrc.txt.gz >);
}

sub _build_packages_details ($self) {
   return $self->target->child(qw< modules 02packages.details.txt.gz >);
}

sub _build_modlist_data ($self) {
   return $self->target->child(qw< modules 03modlist.data.gz >);
}

# function to save contents in a file, providing a name for logging.
# $hint is the target; it can be a GLOB, string "-" (which is assumed to
# be STDOUT), or some other string (interpreted as a path). Undefined or
# empty strings skip saving of the data.
sub _save ($self, $name, $hint, $c) {
   my $output = $hint;
   if (ref($hint) eq '') {
      if (length($hint // '') == 0) {
         INFO "no filename for $name file, skipping";
         return $self;
      }
      elsif ($hint eq '-') {
         $hint   = '<stdout>';
         $output = \*STDOUT;
      }
      else {} # keep as-is
   }
   INFO "saving $name output to $hint";
   $self->_save2($output, scalar(ref($c) ? $c->() : $c));
   return $self;
} ## end sub _save

# actual saving function, tries to do some magic for gzipped files.
sub _save2 ($self, $path, $contents) {
   my ($fh, $is_gz);
   if (ref($path) eq 'GLOB') {
      $fh    = $path;
      $is_gz = 0;
   }
   else {
      my $parent = $path->parent;
      $parent->mkpath unless $parent->exists;
      $fh    = $path->openw_raw;
      $is_gz = $path->stringify =~ m{\.gz$}mxs;
   }

   if ($is_gz) {
      require Compress::Zlib;
      my $gz = Compress::Zlib::gzopen($fh, 'wb');
      $gz->gzwrite($contents);
      $gz->gzclose;
   }
   else {
      binmode $fh;
      print {$fh} $contents;
   }
   return $self;
} ## end sub _save2

sub _do_index ($self) {
   my $basedir = $self->target;
   LOGDIE "target path '$basedir' does not exist" unless -d $basedir;

   # this is the only file that makes some sense in EPAN
   $self->_save( '02packages.details', $self->packages_details,
      sub { # call is avoided if no file for output
         INFO "getting contributions for regenerated index...";
         $self->_index_for;
      },
   );

   # these files contain unuseable data, but it's OK for installers
   $self->_save('01mailrc', $self->mailrc, '');
   $self->_save('03modlist.data', $self->modlist_data,
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
   );

} ## end sub _do_index

sub _index_for ($self) {
   my @index = $self->_index_body_for;
   our $VERSION ||= 'whateva';
   my $n_index = @index;
   my $now = localtime();
   my $header = <<"END_OF_HEADER";
File:         02packages.details.txt
URL:          http://cpan.perl.org/modules/02packages.details.txt.gz
Description:  Package names found in directory \$CPAN/authors/id/
Columns:      package name, version, path
Intended-For: Automated fetch routines, namespace documentation.
Written-By:   epan $VERSION
Line-Count:   $n_index
Last-Updated: $now
END_OF_HEADER
   return join "\n", $header, @index, '';
} ## end sub _index_for

sub _collect_index_for ($self) {
   my $path = $self->target;
   LOGDIE "path '$path' does not exist" unless -d $path;

   my $idpath = $path->child(qw< authors id >);
   my %data_for;
   my $ffr = File::Find::Rule->extras({follow => 1});
   for my $file ($ffr->file->in($idpath->stringify)) {
      INFO "indexing $file";
      my $index_path = path($file)->relative($idpath)->stringify;
      my $dm = Dist::Metadata->new(file => $file);
      my $version_for = $dm->package_versions();

      $data_for{distro}{$index_path} = $version_for;
      (my $bare_index_path = $index_path) =~
        s{^(.)/(\1.)/(\2.*?)/}{$3/}mxs;
      $data_for{bare_distro}{$bare_index_path} = $version_for;

      my %_localdata_for;
      my $score = 0;
      my $previous;
      while (my ($module, $version) = each %$version_for) {
         my $print_version = $version // 'undef';
         DEBUG "data for $module: [$print_version] [$index_path]";
         $_localdata_for{$module} = {
            version => $version,
            distro  => $index_path,
            _file   => $file,
         };
         next if $score != 0;
         next unless exists($data_for{module}{$module});
         $previous = $data_for{module}{$module};
         DEBUG 'some previous version exists';
         if (! defined $version) {
            $score = -1 if defined($previous->{version});
         }
         elsif (defined $previous->{version}) {
            my $tv = version->parse($version);
            my $pv = version->parse($previous->{version});
            $score = $tv <=> $pv;
         }
         DEBUG "score: $score";
      } ## end while (my ($module, $version...))

      DEBUG "FINAL SCORE $score";

      if ($score < 0) { # didn't win against something already in
         DEBUG "marking $file as obsolete";
         $data_for{obsolete}{$file} = 1;
         next;
      }

      DEBUG "getting $file data as winner (for the moment)";
      if ($previous) {
         my $oip = $previous->{distro};
         DEBUG "marking $oip as obsolete";
         $data_for{obsolete}{$previous->{_file}} = 1;
         delete $data_for{module}{$_}
           for keys %{$data_for{distro}{$oip}};
      }
      # copy stuff over to the "official" data for modules
      $data_for{module}{$_} = $_localdata_for{$_} for keys %_localdata_for;
   } ## end for my $file (File::Find::Rule...)
   $self->last_index(\%data_for);
   return %data_for if wantarray();
   return \%data_for;
} ## end sub _collect_index_for

sub _index_body_for ($self) {
   my $path = $self->target;

   my $data_for        = $self->_collect_index_for;
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
} ## end sub _index_body_for


sub initialize ($self, $include_config = 0) {
   my $target = $self->target;
   LOGDIE "target directory $target exists, use update instead"
     if $target->exists;
   $self->update;
   
   if ($include_config) {
      my %config = (
         author  => $self->author,
         helpers => ($self->generate_helpers ? 1 : 0),
      );
      require JSON::PP;
      INFO "saving initial configuration file";
      $self->_save2($target->child('config.json'),
         JSON::PP->new->ascii->canonical->pretty->encode(\%config));
   }

   return $self;
}

sub bare_onboard ($self, @items) { # FIXME path to cpanm
   my $target  = $self->etarget;
   my @command = (
      qw< cpanm --reinstall --quiet --self-contained >,
      ($self->execute_tests ? () : '--notest'),
      '--local-lib-contained' => $target->child('local')->stringify,
      '--save-dists'          => $target->stringify,
      @items,
   );

   my ($out, $err);
   local $SIG{TERM} = sub { WARN "cpanm: received TERM signal, ignoring" };
   INFO "calling @command";
   IPC::Run::run \@command, \undef, \*STDOUT, \*STDERR
      or LOGDIE "cpanm: $? ($err)";

   $self->_inject(grep { -e $_ } @items);

   return $self;
}

sub onboard ($self, @items) { $self->_onboard(@items)->update }

sub last_distlist ($self) {
   sort { $a cmp $b } keys %{$self->last_index->{bare_distro}};
}

sub last_modlist ($self) {
   sort { $a cmp $b }
      map { (sort keys %$_)[0] }
      values $self->last_index->{bare_distro}->%*;
} ## end sub last_modlist

sub update ($self) {
   my $target = $self->etarget;

   INFO 'indexing...';
   $self->_do_index;

   return unless $self->generate_helpers;

   INFO 'saving distlist';
   my @distros = $self->last_distlist;
   $self->_save2($target->child('distlist.txt'), join "\n", @distros, '');

   INFO 'saving modlist';
   my @modules = $self->last_modlist();
   $self->_save2($target->child('modlist.txt'), join "\n", @modules, '');

   my $file = $target->child('install.sh');
   if (! $file->exists) {
      INFO 'saving install.sh';
      $self->_save2($file, __install_script());
      chmod 0777 & ~umask(), $file->stringify;
   } ## end if (!-e $file)

   $file = $target->child('cpanm');
   if (! $file->exists) {
      my $cpanm = which('cpanm');
      INFO "copying cpanm from '$cpanm'";
      File::Copy::copy($cpanm, $file->stringify());
      chmod 0777 & ~umask(), $file->stringify();
   }

   return $self;
}

sub inject ($self, @items) { $self->_inject(@items)->update }

sub _inject ($self, @items) {
   my $target = $self->etarget;

   my $author = $self->author;
   my $first = substr $author, 0, 1;
   my $first_two = substr $author, 0, 2;
   my $repo = $target->child(qw< authors id >, $first, $first_two, $author);
   $repo->mkpath;
   $repo = $repo->stringify;

   File::Copy::copy($_, $repo) for @items;

   return $self;
}

sub __install_script {
   return <<'END_OF_INSTALL';
#!/bin/sh
md="$(dirname "$(readlink -f "$0")")"
target="${EPAN_TARGET:-"$md/local"}"
modlist="${EPAN_MODLIST:-""}"

: ${PERL_CPANM_OPT:="--notest --quiet"}
export PERL_CPANM_OPT

if [ $# -gt 0 ] ; then
   target="$1"
   shift
fi

if [ $# -gt 0 ] ; then
   modlist="$1"
   shift
else
   for name in 'modlist-sorted.txt' 'modlist.txt' ; do
      path="$md/$name"
      [ -r "$path" ] || continue
      modlist="$path"
      break
   done
fi

call_cpanm() {
   "$md/cpanm" \
      --mirror "file://$md" --mirror-only \
      "$@" \
      $(cat "$modlist")
}

if [ -n "$target" ]; then
   call_cpanm -L "$target"
else
   call_cpanm
fi
END_OF_INSTALL
}

sub path_for ($self, $dist) {
   my $c1 = substr $dist, 0, 1;
   my $c2 = substr $dist, 0, 2;
   return $self->target->child(qw< authors id >, $c1, $c2, $dist);
}

sub bare_eject ($self, @items) {
   for my $item (@items) {
      my $path = $self->path_for($item);
      if ($path->exists) {
         INFO "removing '$item'";
         $path->remove;
      }
      else {
         INFO "skipping '$item' (not found)";
      }
   }
   return $self;
}

sub _ancillary_files { qw< cpanm distlist.txt install.sh modlist.txt > }

sub cleanup ($self, $clean_all = undef) {
   my $target = $self->target;

   my @items = qw< local >;
   push @items, $self->_ancillary_files if $clean_all;

   for my $item (@items) {
      my $path = $target->child($item);
      next unless $path->exists;
      if ($path->is_dir) {
         INFO "removing directory '$item'";
         $path->remove_tree({ safe => 0 });
      }
      elsif ($path->exists) {
         INFO "removing file '$item'";
         $path->remove;
      }
      else { } # nothing to remove here
   }

   return $self;
}

sub index ($self) {
   my $target = $self->etarget;
   INFO 'indexing...';
   $self->_do_index;
   return $self;
}

1;
