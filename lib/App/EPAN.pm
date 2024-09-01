package App::EPAN;
use v5.24;
{ our $VERSION = '0.201' }

use Log::Log4perl::Tiny qw< :easy :dead_if_first LOGLEVEL >;
use App::EPAN::Model;
use experimental qw< signatures >;
use Path::Tiny;
use JSON::PP qw< decode_json >;
use Data::Dumper;

use App::Easer::V2 -command => -spec => {
   help        => 'Exclusive Perl Archive Nook',
   description => 'Manage a DarkPAN',
   aliases => [ qw< epan > ],
   config_hash_key => 'merged_v2_008',

   # as a top-level command, the sources also include configuration files
   sources => {
      current => [ qw< +CmdLine +Environment +Default=100 > ],
      final   => [ qw< +JsonFileFromConfig=40 > ],
   },

   options => [
      {
         getopt => 'author|a=s',
         default => 'LOCAL',
         help => 'the author for injecting archive files',
         transmit => 1,
      },
      {
         getopt   => 'clean|C!',
         help     => 'cleanup the "local" directory',
         default  => 0,
         transmit => 1,
      },
      {
         getopt   => 'clean_all|clean-all!',
         help     => 'cleanup the "local" directory and other ancillary files',
         default  => 0,
         transmit => 1,
      },
      {
         getopt   => 'config|c=s',
         help     => 'configuration file',
         environment => 'EPAN_CONFIG',
      },
      {
         getopt => 'helpers!',
         help   => 'generate helper files in addition to index files',
         default => 1,
         transmit => 1,
      },
      {
         getopt   => 'loglevel|log|l=s',
         help     => '',
         default  => 'info',
         environment => 'EPAN_LOGLEVEL',
         transmit => 1,
      },
      {
         getopt   => 'refresh!',
         help     => 'refresh (update/index) after the specific operation',
         default  => 1,
      },
      {
         getopt   => 'target|t=s',
         help     => '',
         default  => 'epan',
         transmit => 1,
         environment => 'EPAN_TARGET',
      },
      {
         getopt      => 'target_config|target-config|T=s',
         help        => 'filename of configuration file inside target',
         default     => 'config.json',
         environment => 'EPAN_TARGET_CONFIG',
         transmit    => 0,
      },
   ],
};

use Moo;
use experimental qw< signatures >;
use namespace::clean;

sub final_commit ($self) {
   my $overall = $self->leaf->config_hash;
   LOGLEVEL($overall->{loglevel});
   return $self;
}

1;
