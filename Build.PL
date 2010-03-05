use Module::Build;

my $build = Module::Build->new(
    module_name => 'Mjollnir',
    license  => 'perl',
    requires => {
        'perl'          => '5.10.1',
        'POE'                           => 0,
        'Net::Pcap'                     => 0,
        'Socket'                        => 0,
        'NetPacket'                     => 0,
        'ORLite'                        => 0,
        'Plack::Request'                => 0,
        'POE::Component::Server::PSGI'  => 0,
    },
);
$build->create_build_script;