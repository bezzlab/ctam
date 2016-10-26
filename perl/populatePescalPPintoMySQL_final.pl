#!/usr/bin/perl
use strict;
use warnings;
use DBD::mysql;
use Text::CSV;
use LWP::UserAgent;
require "misc.pl";

#IMPORTANT: the NULL value (empty value) in MySQL will be retrieved as "" in perl (length = 0)
#this script is based on the converted CSV by Pescal++ from Mascot identification result .dat file
#therefore there are hard-coded parts, e.g. the CSV file layout (header order), Mascot:score as peptide score etc.
$"=">,<";#set array element separator
$|=1;#set autoflush, i.e. print instantly into non-stdout pipe
my $dbi = &getDBI();#subroutine in misc.pl
my $csv = Text::CSV->new ({
	binary    => 1, # Allow special character. Always set this
	auto_diag => 1, # Report irregularities immediately
});
exit;
#all handles in the form of table name followed by type: insert or query. 
#For query type the query columns are listed
#The database handles for experiment level
my $cellLineByNameAndSpeciesQuery = $dbi->prepare("select id from cell_line where name = ? and species = ?");
my $cellLineInsert = $dbi->prepare("insert into cell_line values(null,?,?,null,null,null,null");
my $vendorByNameQuery = $dbi->prepare("select id from vendor where name = ?");
my $vendorInsert = $dbi->prepare("insert into vendor values(null,?,null)");
my $cellLineUsedByCellAndVendorQuery = $dbi->prepare("select id from cell_line_used where cell_line_id = ? AND vendor_id=?");
my $cellLineUsedInsert = $dbi->prepare("insert into cell_line_used values(null,?,?,null,null)");
my $runCellLineCountQuery = $dbi->prepare("select count(*) from run_cell_line where run_id = ? AND cell_line_used_id = ?");
my $runCellLineInsert = $dbi->prepare("insert into run_cell_line values(?,?)");

my $regulatorByNameQuery = $dbi->prepare("select id from regulator where name = ?");
my $regulatorInsert = $dbi->prepare("insert into regulator values (null,?,null,null,null,null,null)");
my $treatmentCountQuery = $dbi->prepare("select count(*) from treatment where run_id = ? and regulator_id = ?");
my $treatmentInsert = $dbi->prepare("insert into treatment values (?,?)");
my $experimentCellLineQuery = $dbi->prepare("select * from experiment_cell_line where experiment_id = ? AND cell_line_used_id=?");
my $experimentCellLineInsert = $dbi->prepare("insert into experiment_cell_line values (?,?)");
my $experimentRegulatorQuery = $dbi->prepare("select * from experiment_regulator where experiment_id = ? AND regulator_id = ?");
my $experimentRegulatorInsert = $dbi->prepare("insert into experiment_regulator values (?,?)");

my $experimentByNameAndCellLineQuery = $dbi->prepare("select id from experiment where name = ? AND submitter = ? AND affiliation = ? AND date = ?");
my $experimentInsert = $dbi->prepare("insert into experiment values(null,?,?,?,?,?,0)");

my $proteinQueryByID = $dbi->prepare("select * from protein where id=?");
my $proteinInsert = $dbi->prepare("insert into protein values (?,?,?,?,null)");
#The database handles for psm level
my $searchParameterByFastaQuery = $dbi->prepare("select * from search_parameter where fasta_file=?");
my $searchParameterInsert = $dbi->prepare("insert into search_parameter values (null,?,?,?,?,?,?,?,?,?,?,?)");
my $searchParameterModificationBySearchQuery = $dbi->prepare("select * from search_parameter_modification where search_parameter_id = ?");
my $searchParameterModificationInsert = $dbi->prepare("insert into search_parameter_modification values (?,?,?)");

my $identificationByRunAndSearchQuery = $dbi->prepare("select id,identification_file from identification where run_id = ? and search_parameter_id = ?");
my $identificationInsert = $dbi->prepare("insert into identification values (null,?,?,?)");

my $softwareByNameQuery = $dbi->prepare("select id from software where name = ?");
my $softwareInsert = $dbi->prepare("insert into software values (null,?,?)");
my $identificationSoftwareByIdentificationAndSoftwareQuery = $dbi->prepare("select * from identification_software where identification_id = ? and software_id = ?");
my $identificationSoftwareInsert = $dbi->prepare("insert into identification_software values (?,?,?,NULL)");

my $runBySpectralLocationQuery = $dbi->prepare("select id from run where spectral_file_location = ?");
my $runBySpectralNameQuery = $dbi->prepare("select id from run where spectral_file_name = ?");
my $runInsert = $dbi->prepare("insert into run values (null,?,?,?,?,null,null)");
my $runInExperimentQuery = $dbi->prepare("select role from runs_in_experiment where experiment_id = ? AND run_id = ?");
my $runInExperimentInsert = $dbi->prepare("insert into runs_in_experiment values (?,?,?)");

my $modificationByAllQuery = $dbi->prepare("select * from modification");
my $modificationInsert = $dbi->prepare("insert into modification values (null,?,null,?,?,null,null)");

my $psmByIdentificationQuery = $dbi->prepare("select count(*) from psm where identification_id = ?");
my $psmInsert = $dbi->prepare("insert into psm values (null,?,?,?,?,?,?,?,?,?,?,?,?)");
my $psmScoreInsert = $dbi->prepare("insert into psm_score values (?,?,?,?)");
my $psmModificationInsert = $dbi->prepare("insert into psm_modification values (?,?,?,?,null,null)");

my %modifications;
$modificationByAllQuery->execute();
while(my @arr=$modificationByAllQuery->fetchrow_array()){
	$modifications{$arr[4]} = $arr[0];
}

my $psmNumberByIdentificationQuery = $dbi->prepare("select count(*) from psm where identification_id = ?");
my $psmByIdentificationAndProteinQuery = $dbi->prepare("select id,spectrum_title from psm where identification_id = ? AND protein_id = ?");

my $bestPsmInsert = $dbi->prepare("insert into best_psm_in_identification values (?,?,?,?,?,?,?,?,?,?,?,?,?)");
my $checkBestPSMdone = $dbi->prepare("select count(*) from psm p, best_psm_in_identification bp where p.id = bp.psm_id AND p.identification_id = ?");

my $peptideBySequenceProteinAndChargeQuery = $dbi->prepare("select id from peptide where sequence = ? AND protein = ? AND charge = ? AND modification_str = ?");
my $peptideInsert = $dbi->prepare("insert into peptide values (null,?,?,?,?,?,?,?,?)");
my $peptideInExperimentByPeptideAndExperimentQuery = $dbi->prepare("select peptide_id from peptide_in_experiment where peptide_id = ? AND experiment_id = ?");
my $peptideInExperimentInsert = $dbi->prepare("insert into peptide_in_experiment values (?,?,?,?, ?,?,?,?, ?,?,?,?, ?,?,?,?)");
my $observedRtQuery = $dbi->prepare("select value from observed_RT where experiment_id = ? AND run_id = ? AND peptide_id = ?");
my $observedRtInsert = $dbi->prepare("insert into observed_RT values(?,?,?,?)");
my $calculatedInsert = $dbi->prepare("insert into calculated_RT values (?,?,?,?)");
my $peakAreaInsert = $dbi->prepare("insert into peak_area values (?,?,?,?)");

my %proteins;#record whether the protein in the database
my %done_proteins;#map of the protein id used in CSV which may be obselete and protein id stored in the database
my %cell_lines;
my %vendors;
my %cell_lines_used;
my %regulators;
my $allProteinQuery = $dbi->prepare("select id,accession from protein");
$allProteinQuery->execute();
while (my ($id,$acc)=$allProteinQuery->fetchrow_array()){
	$done_proteins{$id}=$id;
	$done_proteins{$acc}=$id;
}

open my $expFh, "<", "experiment list.csv";#the file lists all experiments which need to be processed
$csv->getline ($expFh);#remove header
while(my $row = $csv->getline ($expFh)) {
#	Experiment name,folder name,submitter,affiliation,date,cell line,species,vendor
#   date needs to be in the format of yyyy/mm/dd
	my ($name,$dir,$submitter,$affiliation,$date,$description)=@$row;
	next if (substr($name,0,1) eq "#");#skip the lines starting with # which make it possible to avoid already processed experiments while still keep them "visiable"
	print "Parsing the data for experiment $name in the folder $dir ".localtime."\n";
#	print "Cell Line Used id $cell_line_used_id\n";

	my $experiment_id = -1;
	my $count = $experimentByNameAndCellLineQuery->execute($name,$submitter,$affiliation,$date);
	if ($count==0){
		$experimentInsert->execute($name,$submitter,$affiliation,$date,$description);
		$experiment_id=$dbi->last_insert_id(undef,undef,undef,undef);
	}else{
		($experiment_id) = $experimentByNameAndCellLineQuery->fetchrow_array();
	}
	print "Experiment $experiment_id\n";

	#Now start to deal with the actual experiment data
	#metadata needs to be dealt with first to establish which run and identification the psms belong to
	#according to spectral file and identification file name so they MUST be identifical across two files
	my %spectral_files;
	my %identification_files;
	my %total_variable_mod_order;
	my %run_names;
	my %experiment_regulators;
	my %experiment_cell_lines;

	print "Parsing metadata file at ".localtime."\n";
	open my $metaFh, "<", "$dir//metadata.csv" or die "metadata: $!";
	$csv->getline ($metaFh);#remove header
	while(my $row = $csv->getline ($metaFh)) {
		my ($role,$spectral_file,$identification_file,$cell_line_str,$cell_line_species_str,$vendor_str,$regulator_str,$software_names_str,$software_CV_accessions_str,$software_versions_str,$fasta_file,$enzyme,$peptide_tolerance,$peptide_tolerance_unit,$product_tolerance,$product_tolerance_unit,$miscleavage,$min_charge,$max_charge,$species,$species_taxo_id,$fixed_modifications,$variable_modifications) = @$row;
		#locate run id according to the spectral file either as location (preferred as less chance to be duplicate) or filename
		#run is determined by the spectral file, i.e. one spectral file one run
		next if (substr($role,0,1) eq "#");
		my $run_id=-1;
		my $separator="";
		if(index($spectral_file,"\\")>-1){
			$separator = "\\\\";
		}elsif(index($spectral_file,"\/\/")>-1){
			$separator = "\/\/\/\/";
		}

		if (length $separator>0){
			my $count = $runBySpectralLocationQuery->execute($spectral_file);
			($run_id) = $runBySpectralLocationQuery->fetchrow_array() if($count>0);
		}else{#no separator found, more like just the file name, not the location
			my $count = $runBySpectralNameQuery->execute($spectral_file);
			($run_id) = $runBySpectralNameQuery->fetchrow_array() if($count>0);
		}
		if ($run_id==-1){#new run
			my $name;
			my $location;
			if(length $separator>0){
				$location = $spectral_file;
				my @tmp = split($separator,$location);
				$name = $tmp[-1];
			}else{
				$name = $spectral_file;
				undef $location;
			}
			my $idx = rindex($name,".");
			my $format = uc(substr($name,$idx+1));
			my $run_name = substr($name,0,$idx);
			#print "<$run_name>,<$name>,<$format>,<$location>\n";
			$runInsert->execute($run_name,$name,$format,$location);
			$run_id = $dbi->last_insert_id(undef,undef,undef,undef);
		}

		my @cell_lines = split(",",$cell_line_str);#name cannot be empty in mzidentml
		my @cell_line_species = split(",",$cell_line_species_str);
		my @vendors = split(",",$vendor_str);
		if(scalar @cell_lines != scalar @cell_line_species){
			print "the number of cell line names does not match to the number of cell line species for spectral file $spectral_file and identification $identification_file\n";
			next;
		}
		for (my $i=0;$i<scalar @cell_lines;$i++){
			my $cell_line = $cell_lines[$i];
			my $cell_line_species = $cell_line_species[$i];
			my $cell_line_id=-1;
			if (exists $cell_lines{"${cell_line}-${cell_line_species}"}){#processed in the previous run-identification or other experiment
				$cell_line_id = $cell_lines{"${cell_line}-${cell_line_species}"};
			}else{
				$count = $cellLineByNameAndSpeciesQuery->execute($cell_line,$cell_line_species);
				if($count == 0){
					$cellLineInsert->execute($cell_line,$cell_line_species);
					$cell_line_id = $dbi->last_insert_id(undef,undef,undef,undef);
				}else{
					($cell_line_id) = $cellLineByNameAndSpeciesQuery->fetchrow_array()
				}
				$cell_lines{"${cell_line}-${cell_line_species}"} = $cell_line_id;
			}

#			print "cell line $cell_line_id for name $cell_line and species $cell_line_species\n";
			my $vendor;
			if (length $vendor_str == 0){
				$vendor = "Unknown";
			}else{
				$vendor = $vendors[$i];
				$vendor= "Unknown" if (length $vendor == 0);
			}
			my $vendor_id = -1;
			if (exists $vendors{$vendor}){
				$vendor_id = $vendors{$vendor};
			}else{
				$count = $vendorByNameQuery->execute($vendor);
				if($count == 0){
					$vendorInsert->execute($vendor);
					$vendor_id = $dbi->last_insert_id(undef,undef,undef,undef);
				}else{
					($vendor_id) = $vendorByNameQuery->fetchrow_array();
				}
				$vendors{$vendor} = $vendor_id;
			}
#		print "vendor $vendor_id\n";
			my $cell_line_used_id = -1;
			if (exists $cell_lines_used{$cell_line_id-$vendor_id}){
				$cell_line_used_id = $cell_lines_used{$cell_line_id-$vendor_id};
			}else{
				$count = $cellLineUsedByCellAndVendorQuery->execute($cell_line_id,$vendor_id);
				if ($count == 0){
					$cellLineUsedInsert->execute($cell_line_id,$vendor_id);
					$cell_line_used_id = $dbi->last_insert_id(undef,undef,undef,undef);
				}else{
					($cell_line_used_id) = $cellLineUsedByCellAndVendorQuery->fetchrow_array();
				}
				$cell_lines_used{$cell_line_id-$vendor_id} = $cell_line_used_id;
			}		

			$runCellLineCountQuery->execute($run_id,$cell_line_used_id);
			($count) = $runCellLineCountQuery->fetchrow_array();
			$runCellLineInsert->execute($run_id,$cell_line_used_id) if ($count==0);
			$experiment_cell_lines{$cell_line_used_id}=1;
		}

		my @regulators=split(",",$regulator_str);#multiple regulators are allowed which is separated by ","
		foreach my $regulator(@regulators){
			my $regulator_id;
			if(exists $regulators{$regulator}){
				$regulator_id = $regulators{$regulator};
			}else{
				$count = $regulatorByNameQuery->execute($regulator);
				if ($count == 0){
					$regulatorInsert->execute($regulator);
					$regulator_id = $dbi->last_insert_id(undef,undef,undef,undef);
				}else{
					($regulator_id) = $regulatorByNameQuery->fetchrow_array();
				}
				$regulators{$regulator} = $regulator_id;
			}
			$treatmentCountQuery->execute($run_id,$regulator_id);
			($count) = $treatmentCountQuery->fetchrow_array();
			$treatmentInsert->execute($run_id, $regulator_id) if ($count==0);
			$experiment_regulators{$regulator_id}=1;
		}

		$spectral_files{$spectral_file} = $run_id;
		my @elmts = split($separator,$spectral_file);
		my $suffix_idx = rindex($elmts[-1],".");
		$run_names{substr($elmts[-1],0,$suffix_idx)}=$run_id;

		$count = $runInExperimentQuery->execute($experiment_id,$run_id);
		if($count == 0){
			$runInExperimentInsert->execute($run_id,$experiment_id,$role);
		}else{
			my ($existing_role) = $runInExperimentQuery->fetchrow_array();
			if ($role ne $existing_role){
				print "$spectral_file has a different role in the file ($role) from the existing value in the database($existing_role)\n";
				next;
			}
		}

		#as identification table has two foreign keys: run_id, search_parameter_id
		#so next step is to get search_parameter id
		my %mods_in_csv;
		my %variable_mod_order;
		my @fixed = split(",",$fixed_modifications);
		my @fixed_mods_ids;
		foreach my $fixed (@fixed){
			&checkModificationByDisplay($fixed);
			push(@fixed_mods_ids,$modifications{$fixed});
			$mods_in_csv{$modifications{$fixed}}=1;
		}
		my @variables = split(",",$variable_modifications);
		my @variable_mods_ids;
		my $order = 0;
		foreach my $variable(@variables){
			&checkModificationByDisplay($variable);
			$order++;
			$variable_mod_order{$order} = $variable;
			push(@variable_mods_ids,$modifications{$variable});
			$mods_in_csv{$modifications{$variable}}=0;
		}
		#search parameter is determined by every single parameter
		$searchParameterByFastaQuery->execute($fasta_file);
		my @search_parameter_id_candidates;#introduced due to same parameter set can couple with different modification settings
		while(my @arr=$searchParameterByFastaQuery->fetchrow_array()){
			my ($id_in_db,$fasta_file_in_db,$enzyme_in_db,$peptide_tolerance_in_db,$peptide_tolerance_unit_in_db,$product_tolerance_in_db,$product_tolerance_unit_in_db,$miscleavage_in_db,$min_charge_in_db,$max_charge_in_db,$species_in_db,$species_taxo_id_in_db)=@arr;

			#if value not equal => not same search parameter => skip to the next one in the database
			next if($enzyme ne $enzyme_in_db);
			next if($peptide_tolerance != $peptide_tolerance_in_db);
			next if($peptide_tolerance_unit ne $peptide_tolerance_unit_in_db);
			next if($product_tolerance != $product_tolerance_in_db);
			next if($product_tolerance_unit ne $product_tolerance_unit_in_db);
			next if($miscleavage != $miscleavage_in_db);
			next if($min_charge != $min_charge_in_db);
			next if($max_charge != $max_charge_in_db);
			next if($species ne $species_in_db && $species_taxo_id != $species_taxo_id_in_db);
			push(@search_parameter_id_candidates, $id_in_db);
		}

		my $search_parameter_id = -1;
		if (scalar @search_parameter_id_candidates == 0){
		#the empty value for integer type value will cause error, need to undef to be of NULL value in MySQL
			undef $peptide_tolerance if (length $peptide_tolerance==0);
			undef $product_tolerance if (length $product_tolerance==0);
			undef $miscleavage if (length $miscleavage==0);
			undef $min_charge if (length $min_charge==0);
			undef $max_charge if (length $max_charge==0);
			undef $species_taxo_id if (length $species_taxo_id==0);
			$searchParameterInsert->execute($fasta_file,$enzyme,$peptide_tolerance,$peptide_tolerance_unit,$product_tolerance,$product_tolerance_unit,$miscleavage,$min_charge,$max_charge,$species,$species_taxo_id);
			$search_parameter_id = $dbi->last_insert_id(undef,undef,undef,undef);
			#new search parameter, no need to check but just insert modification relationships
			foreach my $mod_id(@fixed_mods_ids){
				$searchParameterModificationInsert->execute($search_parameter_id,$mod_id,1);#1 is the TRUE value
			}
			foreach my $mod_id(@variable_mods_ids){
				$searchParameterModificationInsert->execute($search_parameter_id,$mod_id,0);
			}
		}else{
			#even the search parameter is found, a further check is needed on modification
			foreach my $search_parameter_id_candidate(@search_parameter_id_candidates){
				$searchParameterModificationBySearchQuery->execute($search_parameter_id_candidate);
				my $flag = 1;#when flag =0 it means that at least one modification does not match
#				print "current search parameter: $search_parameter_id_candidate\n";
				my %tmp = %mods_in_csv;

				while(my @tmp=$searchParameterModificationBySearchQuery->fetchrow_array()){
					my (undef,$mod_id,$isFixed) = @tmp;
					if (exists $tmp{$mod_id} && $tmp{$mod_id} == $isFixed){
						delete $tmp{$mod_id};
					}else{
						$flag = 0;
						last;#this last only breaks this loop, should be able to print "location" if that print statement is not commented.
					}
				}
#				print "location found flag $flag\nsize of mods in csv ".(scalar (keys %tmp))."\n";
				if($flag == 1 && scalar (keys %tmp) == 0){#all modification matches
					$search_parameter_id = $search_parameter_id_candidate;
					last;
				}
			}
#			print "result search parameter: $search_parameter_id\n";
			#no modification setting matched
			if($search_parameter_id==-1){
				undef $peptide_tolerance if (length $peptide_tolerance==0);
				undef $product_tolerance if (length $product_tolerance==0);
				undef $miscleavage if (length $miscleavage==0);
				undef $min_charge if (length $min_charge==0);
				undef $max_charge if (length $max_charge==0);
				undef $species_taxo_id if (length $species_taxo_id==0);
				$searchParameterInsert->execute($fasta_file,$enzyme,$peptide_tolerance,$peptide_tolerance_unit,$product_tolerance,$product_tolerance_unit,$miscleavage,$min_charge,$max_charge,$species,$species_taxo_id);
				$search_parameter_id = $dbi->last_insert_id(undef,undef,undef,undef);
				#new search parameter, no need to check but just insert modification relationships
				foreach my $mod_id(@fixed_mods_ids){
					$searchParameterModificationInsert->execute($search_parameter_id,$mod_id,1);#1 is the TRUE value
				}
				foreach my $mod_id(@variable_mods_ids){
					$searchParameterModificationInsert->execute($search_parameter_id,$mod_id,0);
				}
			}
		}#end of finding search parameter

		#now run_id and search_parameter_id are ready, deal with identification
		my $identification_id = -1;
		#search run (spectral file) and search parameter can apply to different software which generates different identification file
		$identificationByRunAndSearchQuery->execute($run_id,$search_parameter_id);
		while(my @arr=$identificationByRunAndSearchQuery->fetchrow_array()){
			my ($iden_id,$iden_file)=@arr;
			if($iden_file eq $identification_file){
				$identification_id = $iden_id;
				last;
			}
		}
		if($identification_id == -1){
			$identificationInsert->execute($run_id,$identification_file,$search_parameter_id);
			$identification_id = $dbi->last_insert_id(undef,undef,undef,undef);
		}
		$identification_files{$identification_file}=$identification_id;
		#modification string in Mascot uses indice of variable modifications to represent, e.g. 00200300 2nd and 3rd  
		%{$total_variable_mod_order{$identification_id}}=%variable_mod_order;

		#deal with software
		my @sw_names = split(",",$software_names_str);#name cannot be empty in mzidentml
		my @sw_accessions = split(",",$software_CV_accessions_str);
		my @sw_versions = split(",",$software_versions_str);
		if((scalar @sw_names != scalar @sw_versions)||(scalar @sw_names != scalar @sw_accessions)){
			print "the number of software name does not match to the number of software accession or version for spectral file $spectral_file and identification $identification_file\n";
			next;
		}
		for (my $i=0;$i<scalar @sw_names;$i++){
			my $name = $sw_names[$i];
			my $accession = $sw_accessions[$i];
			my $count = $softwareByNameQuery->execute($name);
			my $software_id;
			if ($count == 0){
				$softwareInsert->execute($name,$accession);
				$software_id = $dbi->last_insert_id(undef,undef,undef,undef);
			}else{
				my @tmp = $softwareByNameQuery->fetchrow_array();
				$software_id = $tmp[0];
			}
			my $tmp = $identificationSoftwareByIdentificationAndSoftwareQuery->execute($identification_id,$software_id);
			if($tmp==0){
				$identificationSoftwareInsert->execute($identification_id,$software_id,$sw_versions[$i]);
			}
		}

		foreach my $rid(keys %experiment_regulators){
			$count = $experimentRegulatorQuery->execute($experiment_id,$rid);
			$experimentRegulatorInsert->execute($experiment_id,$rid) if ($count == 0);
		}
		foreach my $clid (keys %experiment_cell_lines){
			$count = $experimentCellLineQuery->execute($experiment_id,$clid);
			$experimentCellLineInsert->execute($experiment_id,$clid) if ($count == 0);
		}

	}#end of reading metadata.csv

	#start to process PSM files which currently is in the form of F******.csv (extracted from Mascot F******.dat files)
	opendir DIR, $dir;
	my @files = readdir DIR;
	foreach my $file(@files){
		next unless ($file=~/^F\d+\.csv$/);
		my $idx = rindex($file,".");
		my $datfile = substr($file,0,$idx).".dat";
		#print "Dealing with $dir\\$file\n";
		unless (exists $identification_files{$datfile} || exists $identification_files{$file}) {
#			print "Identification $datfile is not found in the metadata.\n";
			next;
		}

		my $identification_id;
		if (exists $identification_files{$datfile}){
			$identification_id = $identification_files{$datfile};
		}else{
			$identification_id = $identification_files{$file};
		}
		$psmByIdentificationQuery->execute($identification_id);
		my ($psmCount) = $psmByIdentificationQuery->fetchrow_array();
		#print "$psmCount\n";
		if($psmCount>0){#therefore if the run is only partially imported, they all need to be deleted from the database to make it possible to import again
			print "PSMs have been extracted from the file with name $file (converted from $datfile)\nSkipped\n";
			next;
		}

		my %curr_variable_mod_order = %{$total_variable_mod_order{$identification_id}};
		print "Start to process $dir//$file at ".localtime."\n";
		open my $fh, "<", "$dir//$file" or die "$file: $!";
		$csv->getline($fh);
		my $record_count = 0;
		while (my $row = $csv->getline ($fh)) {
			$record_count++;
			my ($protein,$desc,$peptide,$modification,$mz,$rt,$charge,$observed_mw,$delta,$mod_pos,$start,$end,$pep_score,$pep_score_2nd,$pep_expectancy,$pep_expectancy_2nd,$pro_score,$coverage,$title,$peptide_2nd,$filename,$total_ion_intensity,$errorP,$q_value)=@$row;
			#search Uniprot to get id, accession and description which make it possible to only compare protein id
			my $protein_id;
			my $acc;
			my $gene;
			if (exists $done_proteins{$protein}){
				$protein_id = $done_proteins{$protein};
			}else{
				my $tmp = &getProteinInfoFromUniprotSingle($protein);
				if (length $tmp == 0){#no information found on UniProt e.g. protein obsolete or network error then use information stored in CSV
					$protein_id = $protein;
					$acc = $protein;
					if ($desc=~/\sGN=(\S+)\s/){
						$gene = $1;
					}
				}else{
					($protein_id,$acc,$gene)=split("\t",$tmp);
					if (length $gene > 20){#one protein may have many genes, then try to get the gene preferred
						if ($desc=~/\sGN=(\S+)\s/){
							my $alternative = $1;
							$gene = $alternative if (index($gene,$alternative)>-1);
						}
					}
				}
				$done_proteins{$protein}=$protein_id;

				unless (exists $proteins{$protein_id}){#the protein has been dealt with in the current file
					my $num = $proteinQueryByID->execute($protein_id);
					$proteinInsert->execute($protein_id,$acc,$desc,$gene) if ($num == 0);
					$proteins{$protein_id}=1;
				}
			}
			$psmInsert->execute($identification_id,$title,$peptide,$protein_id,$start,$end,$pro_score,1,$rt,$charge,$mz,$total_ion_intensity);
			my $firstPSMid = $dbi->last_insert_id(undef,undef,undef,undef);
			$psmScoreInsert->execute($firstPSMid,"Mascot:score","MS:1001171",$pep_score) if(length $pep_score>0);
			$psmScoreInsert->execute($firstPSMid,"Mascot:expectation value","MS:1001172",$pep_expectancy) if(length $pep_expectancy>0);

			#the mod_pos string has a ' at the beginning
			if ($mod_pos=~/(\d+)/){
				$mod_pos = $1;
			}
			#print "<$mod_pos>\n";
			my @mod_positions = split("",$mod_pos);
			for (my $i=1;$i<(scalar @mod_positions)-1;$i++){
				my $curr = $mod_positions[$i];
				next if ($curr==0);
				my $aa = substr($peptide,$i-1,1);
				my $curr_mod = $curr_variable_mod_order{$curr};
				my $curr_mod_idx = $modifications{$curr_mod};
				$psmModificationInsert->execute($firstPSMid,$curr_mod_idx,$i,$aa);
#			print "at position $i with index $curr\tmod is $curr_mod (in the database id is $curr_mod_idx) on $aa\n";
			}

			if(length $peptide_2nd>0){
				$psmInsert->execute($identification_id,$title,$peptide_2nd,undef,undef,undef,undef,2,undef,undef,undef,undef);
				my $secondPSMid = $dbi->last_insert_id(undef,undef,undef,undef);
				$psmScoreInsert->execute($secondPSMid,"Mascot:score","MS:1001171",$pep_score_2nd) if(length $pep_score_2nd>0);
				$psmScoreInsert->execute($secondPSMid,"Mascot:expectation value","MS:1001172",$pep_expectancy_2nd) if(length $pep_expectancy_2nd>0);
			}
			print "Processed $record_count records\n" if (($record_count%500)==0);
		}
	}
	print "Finished parsing PSM files at ".localtime."\n";

	print "Start parsing best PSM files\n";
	foreach my $file(@files){
		next unless ($file=~/^pF\d+\.csv$/);
		my $idx = rindex($file,".");
		my $datfile = substr($file,1,$idx)."dat";#start from location 1 to remove p from pF**** file name

		unless (exists $identification_files{$datfile}) {
#			print "Identification $datfile is not found in the metadata.\n";
			next;
		}

		print "Dealing with $dir\\$file at ".localtime."\n";
		my $identification_id = $identification_files{$datfile};
		$psmNumberByIdentificationQuery->execute($identification_id);
		my ($psmCount) = $psmNumberByIdentificationQuery->fetchrow_array();
		if($psmCount==0){
			print "No PSMs have been extracted from the file with name $file (converted from $datfile), which makes no sense to parse best PSM csv file\nSkipped\n";
			next;
		}
		print "There are $psmCount PSMs for $datfile\n";
		$checkBestPSMdone->execute($identification_id);
		my ($bestPSMcount) = $checkBestPSMdone->fetchrow_array();
		if ($bestPSMcount>0){
			print "There are $bestPSMcount records in the database for $file which indicates the best PSMs have already been processed. Skipped\n";
			next;
		}

		open my $fh, "<", "$dir//$file" or die "$file: $!";
		$csv->getline($fh);
		my $count = 0;
		my %psm_ids;
		while (my $row = $csv->getline ($fh)) {
			$count++;
			my ($csvAcc,$desc,$peptide,$modification,$mz,$bestRt,$charge,$mod_pos,$max_ppm,$min_ppm,$mean_ppm,$minRt,$maxRt,$pro_score,$max_expectancy,$mean_expectancy,$max_score,$mean_score,$num_PSMs,$pep_start,$pep_end,$max_delta,$title,$filename,undef,undef,$pFDR,$total_ion_intensity)=@$row;
			my $acc;
			#in theory the following if statement is redundant. However when anything wrong in the previous step then resume, the protein may not be in the memory, i.e. done_proteins
			if(exists $done_proteins{$csvAcc}){
				$acc = $done_proteins{$csvAcc};
			}else{ 
				my $tmp = &getProteinInfoFromUniprotSingle($csvAcc);
				if (length $tmp == 0){#no information found on UniProt e.g. protein obsolete then use information stored in CSV
					$acc = $csvAcc;
				}else{
					($acc)=split("\t",$tmp);
				}
				$done_proteins{$csvAcc}=$acc;
			}

			unless (exists $psm_ids{$acc}){
				my $num = $psmByIdentificationAndProteinQuery->execute($identification_id,$acc);
				if ($num == 0){
					print "No psm found for protein $acc, please make sure the psm csv has been processed or the best psm and psm csv files match\n";
					next;
				}
				while(my ($psm_id,$spectrum_title)=$psmByIdentificationAndProteinQuery->fetchrow_array()){
					$psm_ids{$acc}{$spectrum_title} = $psm_id;
				}
			}
			unless (exists $psm_ids{$acc}{$title}) {
				print "No psm found with spectrum title $title from protein $acc, please make sure the psm csv has been processed or the best psm and psm csv files match\n";
				next;
			}
#			print "psm $best_psm_id with title $title\n";
			my $best_psm_id = $psm_ids{$acc}{$title};
			$bestPsmInsert->execute($best_psm_id,$max_score,$mean_score,$max_delta,$min_ppm,$max_ppm,$mean_ppm,$minRt,$maxRt,$max_expectancy,$mean_expectancy,$num_PSMs,$total_ion_intensity);
			print "Processed $count records\n" if (($count%500)==0);
		}
	}
	print "Finish parsing best PSM files (pF**** files) at ".localtime."\n";

	print "Start parsing combined peptide data\n";
	open my $fh, "<", "$dir//combiPeptData.csv" or die "reading combiPeptData: $!";
	#find the location of the observed RT columns
	my @headers = @{$csv->getline($fh)};
	my $run_header_idx = -1;
	my $num_columns = scalar @headers;
	my %run_id_order;
	for (my $i = $num_columns-1;$i>1;$i--){
		if (length $headers[$i]==0){
			$run_header_idx = $i+1;
			last;
		}
		#the if statement is for the metadata only cover part of the runs in the combiPeptData, e.g. one out of several cell lines, or only several inhibitors 
		$run_id_order{$i} = $run_names{$headers[$i]} if (exists $run_names{$headers[$i]});
#		print "column $i\t$headers[$i]\trun id $run_names{$headers[$i]}\n";
	}
#	foreach (keys %run_id_order){
#		print "column index <$_> run id <$run_id_order{$_}>\n";
#	}
#	exit;

	my %peptide_database_id; #keys are Pedro's database id, values are the peptide ids in the database
	#print "$run_header_idx\t$headers[$run_header_idx]\n";
	while (my $row = $csv->getline ($fh)) {
		my @arr = @$row;
		my ($acc,$desc,$peptide,$modification,$mz,$bestRt,$charge,$mod_pos,$max_ppm,$min_ppm,$mean_ppm,$minRt,$maxRt,$pro_score,$max_expectancy,$mean_expectancy,$max_score,$mean_score,$num_PSMs,$pep_start,$pep_end,$max_delta,$title,$filename,undef,undef,$pFDR,$total_ion_intensity,undef,undef,$database_id)=@arr;
		$acc = $done_proteins{$acc};
		#print "$acc\t$peptide\t$database_id\n";

		#this step makes sure that all modifications are displayed in the alphabetic order which makes it comparable
		my $mod_str;
		if (length $modification == 0){
			$mod_str = "";
		}else{
			my @mods = split(";",$modification);
			my %mods_count;
			foreach my $mod(@mods){
					my $count = 1;
				my $display;
				if($mod=~/^\s?(\d?)\s?/){
					$count = $1 if (length $1>0);
					$display = $';
				}
				$mods_count{$display} = $count;
			}
			foreach my $tmp(sort {$a cmp $b} keys %mods_count){
				my $count = $mods_count{$tmp};
				$mod_str .= "$count " if ($count>1);
				$mod_str .= "$tmp; ";
			}
			$mod_str = substr($mod_str, 0, (length $mod_str)-2);
		}

		my $num = $peptideBySequenceProteinAndChargeQuery->execute($peptide,$acc,$charge,$mod_str);
		my $peptide_id = -1;
		if ($num > 0){
			($peptide_id) = $peptideBySequenceProteinAndChargeQuery->fetchrow_array();
		}else{
			$peptideInsert->execute($peptide,$acc,$pep_start,$pep_end,$charge,$mz,$mod_str,undef);
			$peptide_id = $dbi->last_insert_id(undef,undef,undef,undef);
		}
		#print "\n\nPeptide id: <$peptide_id> num: <$num>\n\n";
		#valid peptide id must be greater than 0, after the above $num>0 statement, peptide could be either the valid id or 0 which means that fail to insert due to the protein not in the database (only found in the runs not included in the metadata)
		#if just by chance the protein exists, e.g. previous inserted, the peptide will still be inserted
		next if($peptide_id < 1);
		$num = $peptideInExperimentByPeptideAndExperimentQuery->execute($peptide_id,$experiment_id) if($num > 0);#if new peptide, $num is 0 from peptide query
		if($num>0){
			print "There is already record for peptide $peptide with charge $charge in protein $acc in the experiment $experiment_id\n";
		}else{
			$peptideInExperimentInsert->execute($peptide_id,$experiment_id,$bestRt,$min_ppm,$max_ppm,$mean_ppm,$minRt,$maxRt,$pro_score,$max_expectancy,$mean_expectancy,$max_score,$mean_score,$num_PSMs,$max_delta,$total_ion_intensity);
		}

		$peptide_database_id{$database_id} = $peptide_id;
#
		for (my $i=$run_header_idx;$i<$num_columns;$i++){
			$observedRtInsert->execute($experiment_id,$run_id_order{$i},$peptide_id,$arr[$i]) if (exists $run_id_order{$i} && $arr[$i]>0);#only store non-zero value. When retrieving, not exists => value 0
		}
	}

	print "\nNow it is processing calculated RTs at ".localtime."\n";
	open $fh, "<", "$dir//calculatedRTs.csv" or die "reading calculatedRTs: $!";
	#record the locations of the calculated RT/peak area columns
	@headers = @{$csv->getline($fh)};
	$num_columns = scalar @headers;
	%run_id_order=();
	for (my $i = 1;$i<$num_columns-1;$i++){
		$run_id_order{$i} = $run_names{$headers[$i]} if (exists $run_names{$headers[$i]});
	}
	while (my $row = $csv->getline ($fh)) {
		my @arr = @$row;
		my $database_id = substr($arr[0],1);
		next unless (exists $peptide_database_id{$database_id});#if not exists, peptide id < 1 see 20 lines above
		my $peptide_id = $peptide_database_id{$database_id};
		for (my $i = 1;$i<$num_columns-1;$i++){
			$calculatedInsert->execute($experiment_id,$run_id_order{$i},$peptide_id,$arr[$i]) if (exists $run_id_order{$i} && $arr[$i]>0);
		}
	}

	print "\nNow it is processing peak areas at ".localtime."\n";
	open $fh, "<", "$dir//peakAreas.csv" or die "reading peak area: $!";
	#record the locations of the calculated RT/peak area columns
	@headers = @{$csv->getline($fh)};
	$num_columns = scalar @headers;
	%run_id_order=();
	for (my $i = 1;$i<$num_columns-1;$i++){
		$run_id_order{$i} = $run_names{$headers[$i]} if (exists $run_names{$headers[$i]});
	}
	while (my $row = $csv->getline ($fh)) {
		my @arr = @$row;
		my $database_id = substr($arr[0],1);
		next unless (exists $peptide_database_id{$database_id});
		my $peptide_id = $peptide_database_id{$database_id};
		for (my $i = 1;$i<$num_columns-1;$i++){
			$peakAreaInsert->execute($experiment_id,$run_id_order{$i},$peptide_id,$arr[$i]) if (exists $run_id_order{$i} && $arr[$i]>0);
		}
	}

	print "Finish experiment $name at ".localtime."\n";

}

sub checkModificationByDisplay(){
	my $display = $_[0];
	unless (exists $modifications{$display}){
		my $mod;
		my $site;
		if ($display=~/\((.+)\)/){
			$mod = $`;
			$site = $1;
		}
		print "mod: <$mod>\tsite: <$site>\n";
		$modificationInsert->execute($mod,$site,$display);
		my $id = $dbi->last_insert_id(undef,undef,undef,undef);
		$modifications{$display} = $id;
	}
}

#use RESTful method to get information from Uniprot using protein ids/accessions
#only accept one parameter which can be either id (e.g. P17535) or accession (e.g. JUND_HUMAN);
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

#use RESTful method to get information from Uniprot using protein ids/accessions
#the group mode does not support accessions as input, ids only, which is the reason why it is not suitable for CTAM
sub getProteinInfoFromUniprotByList(){
	my $ids = join(",",@_);
	#Reference http://www.uniprot.org/help/programmatic_access
	#columns: http://www.uniprot.org/help/uniprotkb_column_names
	#perl: http://rest.elkstein.org/2008/02/using-rest-in-perl.html
	my $url = "http://www.uniprot.org/uniprot/?query=${ids}&format=tab&columns=id,entry%20name,genes(PREFERRED)";
	my $contact = 'j.fan@qmul.ac.uk'; # Please set your email address here to help us debug in case of problems.
	my $agent = LWP::UserAgent->new(agent => "libwww-perl $contact");

	my $response = $agent->get($url);
	while (my $wait = $response->header('Retry-After')) {
  		print STDERR "Waiting ($wait)...\n";
  		sleep $wait;
  		$response = $agent->get($response->base);
	}

	my $content;
	$response->is_success ?
  		$content = $response->content :
  		die 'Failed, got ' . $response->status_line .
    		' for ' . $response->request->uri . "\n";

	my @lines = split("\n",$content);
	for (my $i=0;$i<scalar @lines;$i++){
		print "Line $i: <$lines[$i]>\n";
	}
}
