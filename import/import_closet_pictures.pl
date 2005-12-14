#!/usr/bin/perl -w
use strict;
use warnings;
use DBI;

my $usage = "
Usage: $0 <dir>\n";

my $ROOT_DIR =  $ARGV[0] || die $usage;

my $dbh = DBI->connect('DBI:mysql:netdot:localhost', 
		       'netdot_user',
		       'netdot_pass',
		       { RaiseError => 1 });

my $closet_st = $dbh->prepare("SELECT Closet.id FROM Closet, Site 
                               WHERE Site.number = ? AND Closet.site = Site.id
                               AND Closet.name LIKE ?;");

my $insert_st = $dbh->prepare("INSERT INTO BinFile(bindata, filename, filesize, filetype) VALUES (?, ?, ?, ?);");


my %mimeTypes = ("jpg"  =>"image/jpeg", 
		 "jpeg" =>"image/jpeg", 
		 "gif"  =>"image/gif",
                 "png"  =>"image/png", 
		 "pdf"  =>"application/pdf");

opendir(ROOT, $ROOT_DIR) || die("Can not open directory $ROOT_DIR: $!");

while ( defined(my $site = readdir(ROOT)) ){
    next if ( $site =~ /^\.\.?$/ );
    next if ( -f $site );
    my $sitenumber = $site;
    $sitenumber =~ s/^0+//;
    
    my $SITE_DIR = $ROOT_DIR . "/" . $site;
    opendir(SITE, $SITE_DIR) || die("Can not open directory $SITE_DIR: $!");
    
    while ( defined( my $closet = readdir(SITE) ) ){
        next if ( $closet =~ /^\.\.?$/ || -f $closet);
        $closet_st->execute($sitenumber, $closet);
	
        if ( ! $closet_st->rows() ){
            printf("No rows returned for closet $closet in building $sitenumber.\n");
            next;
        }
        if ( $closet_st->rows() > 1 ){
            die("More than one instance of closet $closet in building $sitenumber.\n");
        }

        my $id = ($closet_st->fetchrow_array())[0];
        my $PIC_DIR = $SITE_DIR . "/" . $closet;
        
        next if ( !opendir(PIC, $PIC_DIR) );
        while (defined(my $picture = readdir(PIC))){
            next if (-d $picture);
           
            my $picdata;
            open(PICTURE, $PIC_DIR . "/" . $picture);
            while (<PICTURE>){
                $picdata .= $_;
            }
            my $size = -s PICTURE;
            my $extension = $1 if ( $picture =~ /\.(\w+)$/ );
            close(PICTURE);

            if ($insert_st->execute($picdata, $sitenumber . "_" . $closet . "_" . $picture, $size, $mimeTypes{lc($extension)})){
                # insert to BinFile went OK, now update our ClosetPicture table.
                my $sql = "INSERT INTO ClosetPicture(closet,binfile) VALUES($id, LAST_INSERT_ID());";
                $dbh->do($sql);
            }

            else{
                printf("insert_st execute failed, errstr is: %s, %s\n", $insert_st->errstr(), $insert_st->err());
                printf("file: %s\n", $sitenumber . "_" . $closet . "_" . $picture);
                printf("size: %s\n", $size);
                printf("mimetype: %s\n", $mimeTypes{lc($extension)});
            }

            printf("Picture: %s/%s\n", $PIC_DIR, $picture);
        }
	
        closedir(PIC);
    }
    
    closedir(SITE);
}

closedir(ROOT);

$closet_st->finish();
$insert_st->finish();
$dbh->disconnect();
