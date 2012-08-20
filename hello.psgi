
# Hello.psgi
my $app = sub {
    my $env = shift;
    my $status = 200;
    my $headers = [];
    my $body = ["hello"];
    return [ $status, $headers, $body ];
};
