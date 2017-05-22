#!/usr/bin/perl
use strict;
use DBD::mysql;
#the input file is generated as followed
#on uniprot website search the term "reviewed:yes AND organism:"Homo sapiens (Human) [9606]"" 
#get all reviewed human sequences and download the fasta file
require "misc.pl";

my $dbi = &getDBI("localhost");
#my $dbi = &getDBI("gio2 insert");
my $proteinByIdQuery = $dbi->prepare("select accession, description, gene from protein where id = ?");
my $proteinInsert = $dbi->prepare("insert into protein values(?,?,?,?,null)");#id, accession, desc, gene, gene id
my $proteinUpdate = $dbi->prepare("update protein set accession = ?, description = ?, gene = ? where id = ?");

if (scalar @ARGV != 1){
	print "Usage: perl parseFastaAndPopulateProteinTable.pl <Swissprot fasta file>";
	exit;
}
open IN,"$ARGV[0]" or die "Can not find the file\n";#the fasta file with standard Uniprot heading

while(my $line=<IN>){
	chomp $line;
#	next if (index ($line,"GN=")>-1);
	if(substr($line,0,1) eq ">"){
		my $id="";
		my $ac="";
		my $gene="";
		my $desc="";
#		print "$line\n";
		if($line=~/sp\|(\S+)\|(\S+)\s+(.+\s+OS=(.+)\s+PE=.+)$/){
			$id = $2;
			$ac = $1;
			$desc = $3;
			my $genePart = $4;
			if ($genePart=~/GN=(.+)$/){
				$gene = $1;
			}
#			print "id <$id>\taccession <$ac>\tdescription <$desc>\tgene <$gene>\n";
			my $found = $proteinByIdQuery->execute($id);
			if ($found == 0){
				$proteinInsert->execute($id,$ac,$desc,$gene);
			}else{
				my ($accDB,$descDB,$geneDB) = $proteinByIdQuery->fetchrow_array();
				unless ($accDB eq $ac && $descDB eq $desc && $geneDB eq $gene){
					print "Update $id\n";
					print "before <$accDB> <$descDB> <$geneDB>\n";
					print "after <$ac> <$desc> <$gene>\n\n";
					$proteinUpdate->execute($ac,$desc,$gene,$id);
				}
			}
		}
	}
}
