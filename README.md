# NAME

epan - Exclusive Perl Archive Nook

# VERSION

Ask the version number to the script itself, calling:

    shell$ epan --version

# USAGE

    epan [--usage] [--help] [--man] [--version]

    # "create" insists on *not* finding dirname and creating it
    epan create [-t|--target dirname] Module1 [Module2...]

    # "index" indexes directories from Carton too
    epan index [-o|--output filename] [-t|--target dirname]

    # "inject" adds local distribution archives
    epan inject [-t|--target dirname] File1 [File2...]

    # "list-actions" is also "list_actions"
    epan list-actions

    # "list-obsoletes" is also "list_obsoletes"
    epan list-obsoletes [-t|--target dirname]

    # "purge-obsoletes" is also "purge_obsoletes"
    epan purge-obsoletes [-t|--target dirname]

    # "update" is also "add" and "install"
    epan update [-t|--target dirname] Module1 [Module2...]

# EXAMPLES

    # collects all what's needed to install Dancer somewhere
    shell$ epan create -t dancer-stuff Dancer

    # regenerate index in ./modules/02packages.details.txt.gz
    shell$ epan idx -t dancer-stuff

    # prints index on standard output, works on /path/to/minicpan
    shell$ epan idx -o - -t /path/to/minicpan

# DESCRIPTION

This program helps you creating and managing an EPAN - a version of the
CPAN that is trimmed down to your needs for installing specific stuff.

To start with an example, suppose you have to install Dancer and a couple
of its plugins in a machine that - for good reasons - is not connected to
the Internet. It's easy to get the distribution files for Dancer and the
plugins... but what about the dependencies? It can easily become
a nightmare, forcing you to go back and forth with new modules as soon as
you discover the need to install them.

Thanks to [cpanm](https://metacpan.org/pod/cpanm), this is quite easier these days: it can actually do
what's needed with a single command:

    # on the machine connected to the Internet or to a minicpan
    $ cpanm -L xxx --scandeps --save-dists dists \
         Dancer Dancer::Plugin::FlashNote ...

which places all the modules in subdirectory `dists` (thanks to option
`--save-dists`) with an arrangement similar to what you would expect from
a CPAN mirror.

On the target machine, you still have to make some work - e.g. you should
collect the output from the invocation of cpanm above to figure out the
order to use for installing the distribution files. Additionally, the
directory structure that is generated lacks a proper index file (located
in `modules/02package.details.txt.gz`) so it would be difficult to use
the normal toolchain.

[epan](https://metacpan.org/pod/epan) aims at filling up the last mile to get the job done, providing
you with a subdirectory that is ready for deployment, with all the bits in
place to push automation as much as possible. So you can do this:

    # on the machine connected to the Internet or to a minicpan
    $ epan create Dancer Dancer::Plugin::FlashNote ...
    $ tar cvzf epan.tar.gz epan

transfer `dists.tar.gz` to the target machine and...

    # on the target machine
    $ tar xvzf epan.tar.gz
    $ cd epan
    $ ./install.sh

optionally providing an installation target directory:

    $ ./install.sh /path/to/local/perl

The program `epan` is actually a unified access point to several
different tools for manipulating your _exclusive Perl archive nook_. Most
of these commands operate upon a _target directory_ that is where your
EPAN is stored; this can be specified via option `-t` or its longer
version `--target`. By default, the target directory is assumed to be
`epan` in the current directory.

## `add`, `install` and `update`

These commands are synonimous in `epan`, and all help you pull a module
and its dependencies from a CPAN mirror right into your EPAN, regenerating
the index at the end of the process. The syntax is:

    epan add # or install or update \
       [-t|--target directory]
       Module1 [Module2...]

So, in addition to the common option `-t` for setting the right target
directory, it accepts a list of module names to install (with their
dependencies).

## `create` 

This command is almost the same as `add` and its aliases, with the
exception that the target directory MUST NOT already exist when called.

## `index`

Regenerate the index so that tools like `cpanm` are happy about what they
find and treat your target directory as a real CPAN sort-of mirror. The
syntax is the following:

    epan index [-t|--target dirname]

Note that other commands (e.g. `add` or `create`) already do the
indexing. This command can be useful when you have a starting base (i.e.
a compound of modules coming from CPAN and your own distribution) already
arranged in the right directory tree, but you need to generate an index.
For example, this happens when you collect some distribution files using
`cpanm`:

    shell$ cpanminus -L xxx --save-dists dists Mod1 Mod2...

because it saves the needed distributions in `dists` but it does not
generate the index. The same happens when using `carton`.

In these cases, if you want to prepare a pack of modules to carry with your
application, you can do like this:

    $ figure_out_modules > modlist
    $ cpanm -L xxx --save-dists dists $(<modlist)
    $ epan index -t dists
    $ tar cvf dists.tar dists

then carry dists.tar with you, at which point you can:

    $ cpanm --mirror file://$YOURPATH --mirror-only Mod1 Mod2 ...

## `inject`

If you have some local distribution files, e.g. generated by yourself and
not (yet) uploaded to CPAN, you can inject them into a local EPAN. The
syntax is straightforward:

    epan inject \ 
       [-a|--author author-name] \
       [-t|--target dirname] File1 [File2...]

## `list-actions` and `list_actions`

Prints out the list of available commands.

## `list-obsoletes` and `list_obsoletes`

    epan list-obsoletes [-t|--target dirname]

Prints out a list of obsolete distributions in the EPAN. A distribution is
considered _obsolete_ if there is a newer corresponding version in the
EPAN. E.g. suppose that you work on `Acme::Whatever` and inject version
`0.2`:

    epan inject Acme-Whatever-0.2.tar.gz
    # ...

then you work on it some more time, and inject version `0.3`:

    epan inject Acme-Whatever-0.2.tar.gz
    # ...

Now your EPAN contains two distribution packages for `Acme::Whatever`,
one for release `0.2` (which is the obsolete one) and one for the newest
version `0.3`.

## `purge-obsoletes` and `purge_obsoletes`

    epan purge-obsoletes [-t|--target dirname]

Remove (purge) obsolete distribution packages from the EPAN. See above for what
_obsolete_ means.

# OPTIONS

The following options are supported, even though not all actions use them
all:

- -1 | -m | --mailrc

    path to the file `01mailrc.txt.gz`, defaults to
    `authors/01mailrc.txt.gz` inside the target directory

- -2 | -o | --output | --package-details

    path to the file for `02packages.details.txt.gz`, defaults to
    `modules/02packages.details.txt.gz` inside the target directory. Yes, you
    can use `-` with the _usual_ meaning.

- -3 | -l | --modlist | --modlist-data

    path to the file `03modlist.data.gz`, defaults to
    `modules/03modlist.data.gz` inside the target directory.

- -a | --author author-name

    module author to use when doing injection of local distribution packages

- --help

    print a somewhat more verbose help, showing usage, this description of
    the options and some examples from the synopsis.

- --man

    print out the full documentation for the script.

- -t | --target dirname

    set the directory of the root for the EPAN to work on. Defaults to the
    sub-directory `epan` in the current directory. This option applies to all
    commands except `list-actions` and `index`.

- --usage

    print a concise usage line and exit.

- --version

    print the version of the script.

# CONFIGURATION AND ENVIRONMENT

epan requires no configuration files. The following environment variable
is honored:

- `EPAN_AUTHOR`

    set the name of the _pause account_ to use for indexing. Defaults to
    `LOCAL`. It is overridden by `--author`.

# DEPENDENCIES

Runs on perl 5.012, adapt it if you want to run on something older :-)

The following non-core modules are used:

- **Dist::Metadata**
- **Path::Class**
- **File::Find::Rule**
- **Log::Log4perl::Tiny**

# BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests through
[https://github.com/polettix/epan/issues](https://github.com/polettix/epan/issues).

# AUTHOR

Flavio Poletti `polettix@cpan.org`

# LICENCE AND COPYRIGHT

Copyright (C) 2011-2021 by Flavio Poletti `polettix@cpan.org`.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

> [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
