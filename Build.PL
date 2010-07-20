use Module::Build;

my $build = Module::Build->new(
    module_name     => 'Mjollnir',
    license         => 'perl',
    create_license  => 1,
    share_dir       => 'share',
    requires => {
        'perl'                          => 5.010,
        'Cwd'                           => 0,
        'File::HomeDir'                 => 0,
        'File::ShareDir'                => 0,
        'File::Spec'                    => 0,

        'AnyEvent'                      => 5.26,

        'DBI'                           => 0,
        'DBD::SQLite'                   => 0,

        'Net::Netmask'                  => 0,
        'Socket'                        => 0,
        'Net::Pcap'                     => 0,
        'NetPacket::Ethernet'           => 0,
        'NetPacket::IP'                 => 0,
        'NetPacket::UDP'                => 0,

        'Plack'                         => 0.9930,
        'Plack::Request'                => 0,
        'Plack::MIME'                   => 0,
        'Plack::App::File'              => 0,
        'Plack::Middleware::ConditionalGET' => 0,
        'Plack::Middleware::StackTrace' => 0,
        'Plack::Middleware::AccessLog'  => 0,

        'Twiggy'                        => 0.1005,
        'Twiggy::Server'                => 0,
        'Template'                      => 0,
        ($^O eq 'MSWin32') ? (
            'Win32'                         => 0,
            'Win32::API'                    => 0,
        ) : (),
    },
    build_requires => {
        'File::Find'                    => 0,
        'Test::More'                    => 0,
    },
);
$build->create_build_script;
