#!/usr/bin/perl
use strict;
use warnings;
use DBD::mysql;
use Data::Dumper;
use utf8;
use LWP::UserAgent;
require "misc.pl";
binmode(STDOUT, ":utf8");
#print "GSK-3 α/β"; ###NOTE: in the command prompt, need to type chcp 65001 to set prompt into utf8
#exit;
#then need to make sure mysql connection is utf8-compatiable https://en.wikibooks.org/wiki/Perl_Programming/Unicode_UTF-8
#check utf8 character in mysql remember to use option --default_character_set=utf8
#my $dbi = &getDBI("gio2 insert");
my $dbi = &getDBI("localhost");
my $proteinCheckHandle = $dbi->prepare("select * from protein where id = ?");
my $proteinInsertHandle = $dbi->prepare("insert into protein values (?,?,null,?,null)");
my $handleInsert = $dbi->prepare("insert into kinase values (?,?,?)");
#open my $fh, "<:encoding(utf-8)", "inhibitor table data.txt";
open my $fh, "<:encoding(utf-8)", "resultKinase.txt";#read in file in utf8 mode
my $count=1;
while (my $line=<$fh>){
	chomp($line);
	my @arr = split("\t",$line);
#	print "$count: display <$arr[0]> id <$arr[1]> group <$arr[2]>\n";
	my $found = $proteinCheckHandle->execute($arr[1]);
	if($found==0){
		my $tmp = &getProteinInfoFromUniprotSingle($arr[1]);
		my ($protein_id,$acc,$gene);
		if (length $tmp == 0){#no information found on UniProt e.g. protein obsolete or network error then use information stored in CSV
			$protein_id = $arr[1];
			$acc = $arr[1];
			$gene = "";
		}else{
			($acc,$protein_id,$gene)=split("\t",$tmp);
		}
		print "Protein $protein_id with accession $acc and gene $gene is inserted\n";
		$proteinInsertHandle->execute($protein_id,$acc,$gene);
	}
	$handleInsert->execute($arr[0],$arr[1],$arr[2]);
	$count++;
}

sub getProteinInfoFromUniprotSingle(){
	my $id = $_[0];
	#Reference http://www.uniprot.org/help/programmatic_access
	#columns: http://www.uniprot.org/help/uniprotkb_column_names
	#perl: http://rest.elkstein.org/2008/02/using-rest-in-perl.html
	my $url = "http://www.uniprot.org/uniprot/?query=$id&format=tab&columns=id,entry%20name,genes(PREFERRED)";
	my $contact = 'j.fan@qmul.ac.uk'; # Please set your email address here to help us debug in case of problems.
	my $agent = LWP::UserAgent->new(agent => "libwww-perl $contact");

	my $response = $agent->get($url);
	while (my $wait = $response->header('Retry-After')) {
  		print STDERR "Waiting ($wait)...\n";
  		sleep $wait;
  		$response = $agent->get($response->base);
	}

	my $content="";
	$response->is_success ?
  		$content = $response->content :
  		print 'Failed, got ' . $response->status_line .
    		' for ' . $response->request->uri . "\n";

	return "" if ((length $content)==0);
	my @lines = split("\n",$content);
	#check http://www.uniprot.org/uniprot/?query=p17535&format=tab&columns=id,entry%20name,genes(PREFERRED)
	#which returns a list of matched proteins, so need to check
	foreach my $line(@lines){
		if (index($line,uc($id))>-1) {
			return $line;
		}
	}
	return "";
}
