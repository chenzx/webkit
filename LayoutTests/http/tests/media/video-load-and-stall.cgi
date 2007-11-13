#!/usr/bin/perl -w

use CGI;
use File::stat;

$query = new CGI;
$name = $query->param('name');
$stallAt = $query->param('stallAt');

my $filesize = stat($name)->size;
print "Content-type: video/mp4\n"; 
print "Content-Length: " . $filesize . "\n\n";

open FILE, $name or die;
binmode FILE;
$total = 0;
my ($buf, $data, $n);
while (($n = read FILE, $data, 1024) != 0) {
    $total += $n;
    if ($total > $stallAt) {
        close(FILE);
        return;
    }
    print $data;
}
close(FILE);
