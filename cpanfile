requires 'perl', '5.012';
requires 'App::Easer', '>= 2.007003',
   url => 'https://cpan.metacpan.org/authors/id/P/PO/POLETTIX/App-Easer-2.007003-TRIAL.tar.gz';
requires 'Dist::Metadata';
requires 'Path::Class';
requires 'File::Find::Rule';
requires 'Compress::Zlib';
requires 'Log::Log4perl::Tiny';
requires 'IPC::Run';
requires 'File::Copy';
requires 'File::Which';
requires 'autodie';
requires 'Moo';
requires 'Module::ScanDeps';
requires 'namespace::autoclean';

on develop => sub {
   requires 'Path::Tiny',          '0.084';
   requires 'Template::Perlish',   '1.52';
   requires 'Test::Pod::Coverage', '1.04';
   requires 'Test::Pod',           '1.51';
};
