use Module::Build;

my $build = Module::Build->new(
    module_name => 'Mjollnir',
    license  => 'perl',
    dynamic_config => 0,
    create_license => 1,
    requires => {
        'perl'                          => '5.10.1',
        'POE'                           => 0,
        'Net::Pcap'                     => 0,
        'Socket'                        => 0,
        'NetPacket'                     => 0,
        'DBI'                           => 0,
        'DBD::SQLite'                   => 0,
        'Plack::Request'                => 0,
        'POE::Component::Server::PSGI'  => 0,
    },
    share_dir => 'share',
);
$build->create_build_script;