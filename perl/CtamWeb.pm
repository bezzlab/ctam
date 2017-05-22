package CtamWeb;
use Dancer2;
use DBD::mysql;
use Data::Dumper;
#use Dancer::Plugin::Database;
#development record
#version 0.1  provide APIs for overview, experiment, run, peptide and peak area with self extracted document (/api)
#version 0.2  use universal function getQuantitativeData in all peak related functions
#version 0.3  add APIs for calculated RT and observed RT
#version 0.3.1  improve documentation layout for /api by classifying
#version 0.4  add run entrance to quantitative data
#version 0.4.1 replace space in column names with "_"
#version 0.5  add phosphosite route
#version 0.5.1  add subroutine to check whether one inhibitor(group)/cell line exists in the experiment
#version 0.5.2  add filtering function to phosphosite route
#version 0.6	add group/regulator route
#version 0.7	add kinase/protein route
#version 0.7.1 	add list of proteins/kinases in one experiment
#version 0.7.2 	add list of peptides from a given protein
#version 0.8	add existance route which could be used for search function
#version 0.8.1  add phosphosite to phosphosite route
#version 0.8.2  improve search route by returning matching term
require "misc.pl";

our $VERSION = '0.8.2';

my $dbi; 
my $numExpStr = "select count(*) from experiment";
my $numCellLineStr = "select count(*) from cell_line_used";
my $numRegulatorStr = "select count(*) from regulator";
my $numPeptideStr = "select count(*) from peptide";

my $expAllStr = "select id, name, description from experiment where processed>0";
my $expByIDStr = "select * from experiment where id = ? and processed>0";
my $runByExpIdStr = "select count(*) from runs_in_experiment where experiment_id = ?";
my $peptideByExpIdStr = "select count(*) from peptide_in_experiment where experiment_id = ?";
my $regulatorByExpIdStr = "select count(*) from experiment_regulator where experiment_id = ?";
my $cellLineByExpIdStr = "select count(*) from experiment_cell_line where experiment_id = ?";

my $runInExperimentStr = "select r.id, r.name, rie.group, cl.name from run r,runs_in_experiment rie,run_cell_line rcl,cell_line cl, cell_line_used clu where r.id=rcl.run_id and rcl.run_id = rie.run_id and rcl.cell_line_used_id = clu.id and clu.cell_line_id = cl.id
and rie.experiment_id = ?";
my $runInfoStr = "select r.id as ID, r.name as Name, r.spectral_file_name as 'Spectral file', r.spectral_file_location as Location, i.identification_file as Identification from run r, identification i where r.id = i.run_id and r.id = ?";
my $runInfoExperimentStr = "select r.id as ID, r.name as Name from run r, runs_in_experiment rie where r.id = ? and r.id = rie.run_id and rie.experiment_id=?";
my $runRegulatorStr = "select r.name from treatment t, regulator r where t.run_id = ? and r.id = t.regulator_id";
my $runCellLineStr = "select cl.name from run_cell_line rcl,cell_line cl, cell_line_used clu where rcl.run_id = ? and rcl.cell_line_used_id = clu.id and clu.cell_line_id = cl.id";
my $runByExperiementAndGroupStr = "select r.id, r.name from run r, runs_in_experiment rie where r.id = rie.run_id AND rie.experiment_id = ? and rie.group = ?";
my $runByExperiementAndCellLineStr = "select r.id, r.name from run r, runs_in_experiment rie, cell_line cl, run_cell_line rcl, cell_line_used clu where r.id = rcl.run_id AND rcl.cell_line_used_id = clu.id AND clu.cell_line_id = cl.id AND r.id = rie.run_id AND rie.experiment_id = ? AND cl.name = ?";
my $runByExperiementGroupAndCellLineStr = "select r.id, r.name from run r, runs_in_experiment rie, cell_line cl, run_cell_line rcl, cell_line_used clu where r.id = rcl.run_id AND rcl.cell_line_used_id = clu.id AND clu.cell_line_id = cl.id AND r.id = rie.run_id AND rie.experiment_id = ? and rie.group = ? AND cl.name = ?";

my $peptideAllByExperimentStr = "select p.id, p.sequence ,p.protein, p.charge, p.modification_str from peptide p, peptide_in_experiment pe where pe.experiment_id = ? and pe.peptide_id=p.id order by p.sequence asc, p.id asc";
my $peptideBySequenceAndExperimentStr = "select p.id, p.sequence ,p.protein, p.charge, p.modification_str from peptide p, peptide_in_experiment pe where pe.experiment_id = ? and pe.peptide_id=p.id and p.sequence = ?";
my $proteinByExperimentStr = "select p.protein, count(*) from peptide p, peptide_in_experiment pie where p.id = pie.peptide_id and pie.experiment_id = ? group by p.protein order by count(*) desc, p.protein";
my $kinaseByExperimentStr = "select k.protein_id, count(*) from peptide p, peptide_in_experiment pie,kinase k where p.id = pie.peptide_id and pie.experiment_id = ? and p.protein = k.protein_id group by p.protein order by count(*) desc, p.protein";
my $kinaseInfoStr = "select display as 'Kinase Name', kinase.group as 'Kinase Group' from kinase where protein_id = ?";
my $proteinWithPeptideListStr = "select pie.experiment_id, p.sequence from peptide_in_experiment pie, peptide p where p.protein=? and p.id=pie.peptide_id";
my $proteinWithPeptideInExperimentStr = "select p.sequence, p.charge, p.modification_str from peptide_in_experiment pie, peptide p where p.protein=? and p.id=pie.peptide_id and pie.experiment_id=?";

my $regulatorInGroupStr = "select rie.run_id, re.name from runs_in_experiment rie,treatment t,regulator re where rie.experiment_id = ? and rie.group = ? and rie.run_id = t.run_id and t.regulator_id = re.id";
my $regulatorInExperimentStr = "select re.id, re.name, rie.group, rie.run_id from runs_in_experiment rie,treatment t,regulator re where rie.experiment_id = ? and rie.run_id = t.run_id and t.regulator_id = re.id";
my $regulatorListStr = "select id, name, main_target from regulator";
my $regulatorInfoStr = "select id as ID, name as Name, CAS, formula as 'Formula', main_target as 'Target', mw as 'Molecular Weight', activity_link from regulator where id = ?";
my $regulatorKinaseStr = "select kinase_id from regulator_kinase where regulator_id = ?";

my $groupExistanceStr = "select `group` from runs_in_experiment where experiment_id = ? and `group` = ?";
my $cellExistanceStr = "select cl.name from cell_line cl, experiment_cell_line ecl, cell_line_used clu where ecl.experiment_id = ? AND cl.name = ? AND ecl.cell_line_used_id = clu.id AND clu.cell_line_id = cl.id";
#my $phosphoByPeptideStr = "select p.id, p.sequence, p.protein, p.charge, p.modification_str, fr.group_id, fr.fold_change, fr.pvalue, fr.identified_times from peptide p, final_result fr, cell_line cl, experiment_cell_line ecl, cell_line_used clu where fr.experiment_id = ? AND cl.name = ? AND p.sequence = ? AND p.id = fr.peptide_id AND ecl.experiment_id = fr.experiment_id AND ecl.cell_line_used_id = clu.id AND clu.cell_line_id = cl.id and (fr.fold_change >= ? or fr.fold_change <= ?) and (fr.pvalue <= ? or fr.pvalue = 10) and fr.group_id != \"control\" order by p.id asc";
my $phosphoByPeptideStr = "select p.id, p.sequence, p.protein, p.charge, p.modification_str, pie.phosphorylation_site, fr.group_id, fr.fold_change, fr.pvalue, fr.identified_times from peptide p, peptide_in_experiment pie, final_result fr, cell_line cl, cell_line_used clu where fr.experiment_id = ? AND cl.name = ? AND p.sequence = ? AND p.id = fr.peptide_id AND p.id = pie.peptide_id and pie.experiment_id= fr.experiment_id AND fr.cell_line_used_id = clu.id AND clu.cell_line_id = cl.id and (fr.fold_change >= ? or fr.fold_change <= ?) and (fr.pvalue <= ? or fr.pvalue = 10) and fr.group_id != \"control\" order by p.id asc";
#my $phosphoByRegulatorStr = "select p.id, p.sequence, p.protein, p.charge, p.modification_str, fr.group_id, fr.fold_change, fr.pvalue, fr.identified_times from peptide p, final_result fr, cell_line cl, experiment_cell_line ecl, cell_line_used clu where fr.experiment_id = ? AND cl.name = ? AND fr.group_id = ? AND p.id = fr.peptide_id AND ecl.experiment_id = fr.experiment_id AND ecl.cell_line_used_id = clu.id AND clu.cell_line_id = cl.id and (fr.fold_change >= ? or fr.fold_change <= ?) and (fr.pvalue <= ? or fr.pvalue = 10) and fr.group_id != \"control\" order by p.id asc";
my $phosphoByRegulatorStr = "select p.id, p.sequence, p.protein, p.charge, p.modification_str, pie.phosphorylation_site, fr.group_id, fr.fold_change, fr.pvalue, fr.identified_times from peptide p, peptide_in_experiment pie, final_result fr, cell_line cl, cell_line_used clu where fr.experiment_id = ? AND cl.name = ? AND fr.group_id = ? AND p.id = fr.peptide_id AND p.id = pie.peptide_id and pie.experiment_id= fr.experiment_id AND fr.cell_line_used_id = clu.id AND clu.cell_line_id = cl.id and (fr.fold_change >= ? or fr.fold_change <= ?) and (fr.pvalue <= ? or fr.pvalue = 10) and fr.group_id != \"control\" order by p.id asc";
my $identifiedTimesInControlStr = "select identified_times from final_result where peptide_id = ? and experiment_id = ? and cell_line_used_id = ? and group_id=\"control\"";

#get method
get '/' => sub {
    template 'index'; #template directive Templates all go into the views/
};# Since the subroutine is actually a coderef, it requires a semicolon.
##Get all available APIs (this page)
get '/api' => sub{
	open IN, "lib/CtamWeb.pm";
	my $result="APIs\tDescription\n";
	my $desc = "";
	my $last = "";
	while (my $line=<IN>){
		chomp($line);
		if (index($line,"####")==0){
			$last = "";
			$result .= "\n";
			$result .= substr($line,4);
			$result .= "\n";
			next;
		}
		if (index($line,"##")==0){
			$desc.=substr($line,2);
		}
		if ($line=~/^get\s'(\/.+)'/){
			my (undef,$path) = split("\/",$1);
			#print "<$path> from <$1>\n"; # this can be seen on dancer2 console
			if($path ne $last){
				$result .= "\n" unless ($last eq "");
				$last = $path;
			}
			if(length $desc > 0){
				$result .= "$1\t$desc\n";
			}
			$desc = "";
		}
	}
	return "<pre>\n$result</pre>\n";
};
##Provides the overview of the data stored
get '/overview' => sub {
	&checkDBI();
	my $result = "Experiment\tCell_line\tRegulator\tPeptide\n";

	my $handle = $dbi->prepare($numExpStr);
	$handle->execute();
	my ($count)=$handle->fetchrow_array();
	$result .= "$count";

	$handle = $dbi->prepare($numCellLineStr);
	$handle->execute();
	($count)=$handle->fetchrow_array();
	$result .= "\t$count";

	$handle = $dbi->prepare($numRegulatorStr);
	$handle->execute();
	($count)=$handle->fetchrow_array();
	$result .= "\t$count";

	$handle = $dbi->prepare($numPeptideStr);
	$handle->execute();
	($count)=$handle->fetchrow_array();
	$result .= "\t$count\n";

	return "<pre>\n$result</pre>\n";
#	return $result;
};
##search a term in the database and return the list of experiments containing the term. Parameter: term, a String
get '/search/:term' => sub {
	my $term = params->{"term"};
	&checkDBI();
	my @entities = qw/Experiment Regulator Cell_line Protein Peptide/;
	my @types = qw/equal like/;
	my %hash;#store the handles
	push(@{$hash{Experiment}{like}},"select name,id from experiment where name like ?");
	push(@{$hash{Experiment}{like}},"select description,id from experiment where description like ?");

	push(@{$hash{Regulator}{like}},"select r.name, er.experiment_id from experiment_regulator er, regulator r where er.regulator_id = r.id and r.name like ?");
	push(@{$hash{Regulator}{equal}},"select r.name, er.experiment_id from experiment_regulator er, regulator r where er.regulator_id = r.id and r.cas = ?");

	push(@{$hash{Cell_line}{like}},"select c.name, ecl.experiment_id from experiment_cell_line ecl, cell_line_used clu, cell_line c where ecl.cell_line_used_id = clu.id and clu.cell_line_id = c.id and c.name like ?");
	
	push(@{$hash{Protein}{like}},"select p.protein, pie.experiment_id from peptide_in_experiment pie, peptide p where pie.peptide_id = p.id and p.protein like ?");
	push(@{$hash{Protein}{equal}},"select p.protein, pie.experiment_id from peptide_in_experiment pie, peptide p, protein pro where pie.peptide_id = p.id and pro.id = p.protein and pro.accession = ?");
	
	push(@{$hash{Peptide}{equal}},"select p.sequence, pie.experiment_id from peptide_in_experiment pie, peptide p where pie.peptide_id = p.id and p.sequence = ?");

	my $result = "Type\tMatched_term\tExisting_Experiments\n";
	my $handle;
	my %results;
	foreach my $entity(@entities){
		foreach my $type(@types){
			next unless (exists $hash{$entity}{$type});
			my @handles = @{$hash{$entity}{$type}};
			foreach my $handle_str(@handles){
				$handle = $dbi->prepare($handle_str);
				my $count;
				if ($type eq "like"){
					$count = $handle->execute("%$term%");
				}else{
					$count = $handle->execute($term);
				}

				if ($count>0){
					while (my ($match,$exp_id)=$handle->fetchrow_array()){
						$results{$entity}{$match}{$exp_id}=1;
					}
				}
			}
		}
	}
	foreach my $entity(@entities){
		if(exists $results{$entity}){
			my %tmp = %{$results{$entity}};
			foreach my $match(keys %tmp){
				my @tmp = sort {$a <=> $b} keys %{$tmp{$match}};
				my $tmp = join (", ",@tmp);
				$result .= "$entity\t$match\t$tmp\n";
			}
		}else{
			$result .= "$entity\tNo match\t\n";
		}
	}
	return "<pre>\n$result</pre>\n";
};
#Metadata
##Retrieves the list of experiments including experiment ids, descriptions.
get '/experiment/list' => sub {
	&checkDBI();
	my $handle = $dbi->prepare($expAllStr);
	$handle->execute();
	my $result = "ID\tName\tDescription\n";

	while(my @arr=$handle->fetchrow_array()){
		my $line = join("\t",@arr);
		$result .= "$line\n";
	}
	return "<pre>\n$result</pre>\n";
};
##Gets the details of specified experiment. Parameter: experiment id, integers.
get '/experiment/:exp_id' => sub {
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	&checkDBI();
	my $result = "Key\tValue\n";
	my $handle = $dbi->prepare($expByIDStr);
	my $exist = $handle->execute($exp_id);
	if ($exist==0){
		return "No experiment existing with given id $exp_id";
	}
	my %hash = %{$handle->fetchrow_hashref()};
	my @keys = qw/id name description date submitter affiliation/;
	foreach (@keys){
		$result .= "$_\t$hash{$_}\n";
	}

	$handle = $dbi->prepare($runByExpIdStr);
	$handle->execute($exp_id);
	my ($count)=$handle->fetchrow_array();
	$result .= "Number of runs\t$count\n";

	$handle = $dbi->prepare($peptideByExpIdStr);
	$handle->execute($exp_id);
	($count) = $handle->fetchrow_array();
	$result .= "Number of peptides\t$count\n";

	$handle = $dbi->prepare($cellLineByExpIdStr);
	$handle->execute($exp_id);
	($count) = $handle->fetchrow_array();
	$result .= "Number of cell lines\t$count\n";

	$handle = $dbi->prepare($regulatorByExpIdStr);
	$handle->execute($exp_id);
	($count) = $handle->fetchrow_array();
	$result .= "Number of regulators\t$count\n";
	return "<pre>\n$result</pre>\n";
};

# /run/count/experiment/{exp id} covered by /experiment/:id and kind of by /run/list/experiment/:id
##Returns the run list under the given experiment. Parameter: experiment id, integers.
get '/run/list/experiment/:exp_id' => sub {
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	&checkDBI();
	my $handle = $dbi->prepare($runInExperimentStr);
	my $exist = $handle->execute($exp_id);
	if ($exist==0){
		return "No experiment existing with given id $exp_id";
	}

	my $result = "ID\tName\tGroup\tCell_line\n";

	while(my @arr=$handle->fetchrow_array()){
		my $line = join("\t",@arr);
		$result .= "$line\n";
	}
	return "<pre>\n$result</pre>\n";
};
##Get details for the specified run. Parameter:run id, integers               
get '/run/:run_id' => sub {
	my $run_id = params->{"run_id"};
	unless (&checkIntegers($run_id)) {
		return "Wrong parameter: only numbers allowed for run id";
	}
	&checkDBI();
	my $result = "Key\tValue\n";
	my $handle = $dbi->prepare($runInfoStr);
	my $exist = $handle->execute($run_id);
	if ($exist==0){
		return "No run existing with given id $run_id";
	}
	my %hash = %{$handle->fetchrow_hashref()};
	my @keys = ("ID", "Name", "Identification");
	foreach (@keys){
#	foreach (keys %hash){
		$result .= "$_\t$hash{$_}\n";
	}
	my $file = "Spectral file";#, "Location","
	$result .= "$file\t<a href=\"$hash{Location}\">$hash{$file}</a>\n";
#	$result .= "$file\t<a href=\"/credential.txt\">$hash{$file}</a>\n";

	$handle = $dbi->prepare($runRegulatorStr);
	$handle->execute($run_id);
	my @arr;
	while (my ($regulator)=$handle->fetchrow_array()){
		push (@arr, $regulator);
	}
	my $str = join (",",@arr);
	$result .= "Regulators\t$str\n";

	$handle = $dbi->prepare($runCellLineStr);
	$handle->execute($run_id);
	my @arr1;
	while (my ($cell_line)=$handle->fetchrow_array()){
		push (@arr1, $cell_line);
	}
	$str = join (",",@arr1);
	$result .= "Cell lines\t$str\n";
	return "<pre>\n$result</pre>\n";
};

##Get details for the specified group. Parameter:1) group id, strings; 2) Experiment id, integers               
get '/group/:group_id/experiment/:exp_id' => sub {
	my $group = params->{"group_id"};
	return "There are no phosphosites available for the control group, please try another group instead" if (lc($group) eq "control");
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	&checkDBI();
	my $handle = $dbi->prepare($regulatorInGroupStr);
	my $exist = $handle->execute($exp_id,$group);
	if ($exist==0){
		return "No runs existing with given group $group in experiment $exp_id, please refer to /run/list/experiment/$exp_id for all available groups";
	}
	my $result = "Run\tRegulator\n";
	while(my @arr=$handle->fetchrow_array()){
		my $line = join("\t",@arr);
		$result .= "$line\n";
	}
	return "<pre>\n$result</pre>\n";
};

##Gets the regulator list 
get '/regulator/list' => sub {
	&checkDBI();
	my $handle = $dbi->prepare($regulatorListStr);
	$handle->execute();
	my $result = "ID\tName\tMain_target\n";
	while (my ($id,$regulator,$target)=$handle->fetchrow_array()){
		$target = "" unless (defined $target);
		$result .= "$id\t$regulator\t$target\n";
	}
	return "<pre>\n$result</pre>\n";
};



##Gets the regulator list for the given experiment. Parameter: experiment id, integers
get '/regulator/list/experiment/:exp_id' => sub {
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	&checkDBI();
	my $handle = $dbi->prepare($expByIDStr);
	my $exist = $handle->execute($exp_id);
	if ($exist==0){
		return "No experiment existing with given id $exp_id";
	}
	$handle = $dbi->prepare($regulatorInExperimentStr);
	$handle->execute($exp_id);
	my $result = "Regulator_id\tName\tGroup\tRuns\n";
	my %hash;
	my %names;
	while (my ($regulator_id,$regulator,$group,$run_id)=$handle->fetchrow_array()){
		push(@{$hash{$regulator_id}{$group}},$run_id);
		$names{$regulator_id} = $regulator;
	}

	foreach my $regulator_id(sort {$a cmp $b} keys %hash){
		my %tmp = %{$hash{$regulator_id}};
		foreach my $group(sort {$a cmp $b} keys %tmp){
			my $runs = join(",",@{$tmp{$group}});
			$result .= "$regulator_id\t$names{$regulator_id}\t$group\t$runs\n";
		}
	}
	return "<pre>\n$result</pre>\n";
};

##Get details for the specified run. Parameter:regulator id, integers               
get '/regulator/:regulator_id' => sub {
	my $regulator_id = params->{"regulator_id"};
	unless (&checkIntegers($regulator_id)) {
		return "Wrong parameter: only numbers allowed for run id";
	}
	&checkDBI();
	my $result = "Key\tValue\n";
	my $handle = $dbi->prepare($regulatorInfoStr);
	my $exist = $handle->execute($regulator_id);
	if ($exist==0){
		return "No regulator existing with given id $regulator_id";
	}
	my %hash = %{$handle->fetchrow_hashref()};
	my @keys = ("ID", "Name", "CAS", "Formula", "Target", "Molecular Weight");
	foreach (@keys){
		$result .= "$_\t$hash{$_}\n";
	}
	$result .= "Known activity\t<a target=\"_blank\" href=\"http://www.kinase-screen.mrc.ac.uk/screening-compounds/$hash{activity_link}\">$hash{activity_link}</a>\n" if (exists $hash{"activity_link"} && defined $hash{"activity_link"});

	$handle = $dbi->prepare($regulatorKinaseStr);
	$handle->execute($regulator_id);
	my @arr;
	while (my ($kinase)=$handle->fetchrow_array()){
		push (@arr, $kinase);
	}
	my $str = join (",",@arr);
	$result .= "Kinases\t$str\n";

	return "<pre>\n$result</pre>\n";
};
#               /cell_line/count/experiment/{exp id}
#               /cell_line/list/experiment/{exp id}
#               /cell_line/{cell line id}

##Gets the list of detected kinases for the given experiment. Parameter: experiment id, integers
get '/kinase/list/experiment/:exp_id' => sub {
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	&checkDBI();
	my $handle = $dbi->prepare($expByIDStr);
	my $exist = $handle->execute($exp_id);
	if ($exist==0){
		return "No experiment existing with given id $exp_id";
	}
	$handle = $dbi->prepare($kinaseByExperimentStr);
	$handle->execute($exp_id);
	my $result = "Kinase\tNumber_of_detected_peptides\n";
	while (my ($protein,$num)=$handle->fetchrow_array()){
		$result .= "$protein\t$num\n";
	}
	return "<pre>\n$result</pre>\n";
};

##Get details for the specified kinase. Parameter:kinase id, Uniprot protein ID               
get '/kinase/:kinase_id' => sub {
	my $kinase_id = uc(params->{"kinase_id"});
	unless ($kinase_id=~/_HUMAN$/) {
		return "Now only human kinases can be searched and must be in the Uniprot ID format, e.g. AKT1_HUMAN";
	}
	&checkDBI();
	my $result = &getProteinInfo($kinase_id);
	return "No protein matches to the ID $kinase_id" if (length $result==0);
	my $handle = $dbi->prepare($kinaseInfoStr);
	my $exist = $handle->execute($kinase_id);
	return "$kinase_id is not a recognized kinase" if ($exist==0);
	my %hash = %{$handle->fetchrow_hashref()};
	my @keys = ("Kinase Name", "Kinase Group");
	foreach (@keys){
		$result .= "$_\t$hash{$_}\n" if (exists $hash{$_});
	}
	return "<pre>\n$result</pre>\n";
};

##Gets the protein list for the given experiment. Parameter: experiment id, integers
get '/protein/list/experiment/:exp_id' => sub {
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	&checkDBI();
	my $handle = $dbi->prepare($expByIDStr);
	my $exist = $handle->execute($exp_id);
	if ($exist==0){
		return "No experiment existing with given id $exp_id";
	}
	$handle = $dbi->prepare($proteinByExperimentStr);
	$handle->execute($exp_id);
	my $result = "Protein\tNumber_of_detected_peptides\n";
	while (my ($protein,$num)=$handle->fetchrow_array()){
		$result .= "$protein\t$num\n";
	}
	return "<pre>\n$result</pre>\n";
};

##Get details for the specified protein. Parameter:protein id, Uniprot protein ID               
get '/protein/:protein_id' => sub {
	my $protein_id = params->{"protein_id"};
	unless ($protein_id=~/_HUMAN$/) {
		return "Now only human proteins can be searched and must be in the Uniprot ID format, e.g. AKT1_HUMAN";
	}
	&checkDBI();
	my $result = &getProteinInfo($protein_id);
	return "No protein matches to the ID $protein_id" if (length $result==0);
	return "<pre>\n$result</pre>\n";
};

##Get number of identified peptides based on sequence in each experiment for the given protein. Parameter:protein id, Uniprot protein ID               
get '/protein/:protein_id/evidence/experiment/list' => sub {
	my $protein_id = uc(params->{"protein_id"});
	unless ($protein_id=~/_HUMAN$/) {
		return "Now only human proteins can be searched and must be in the Uniprot ID format, e.g. AKT1_HUMAN";
	}
	&checkDBI();
	my $handle = $dbi->prepare($proteinWithPeptideListStr);
	$handle->execute($protein_id);
	my $result = "Experiment\tNumber_of_detected_peptides\n";
	my %hash;
	while (my ($experiment_id,$peptide)=$handle->fetchrow_array()){
		$hash{$experiment_id}{$peptide} = 1;
		$hash{"all"}{$peptide} = 1;
	}
	my %forAll = %{$hash{"all"}};
	delete $hash{"all"};
	foreach my $exp_id(sort {$a <=> $b} keys %hash){
		my %tmp = %{$hash{$exp_id}};
		my $num = scalar keys %tmp;
		$result .= "$exp_id\t$num\n";
	}
	my $num = scalar keys %forAll;
	$result .= "All experiment\t$num\n";
	return "<pre>\n$result</pre>\n";
};

##Get details of identified peptides in the given experiment for the given protein. Parameter: 1) protein id, Uniprot protein ID; 2) experiment id, Integers               
get '/protein/:protein_id/evidence/experiment/:exp_id' => sub {
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $protein_id = uc(params->{"protein_id"});
	unless ($protein_id=~/_HUMAN$/) {
		return "Now only human proteins can be searched and must be in the Uniprot ID format, e.g. AKT1_HUMAN";
	}
	&checkDBI();
	my $handle = $dbi->prepare($expByIDStr);
	my $exist = $handle->execute($exp_id);
	if ($exist==0){
		return "No experiment existing with given id $exp_id";
	}
	$handle = $dbi->prepare($proteinWithPeptideInExperimentStr);
	$handle->execute($protein_id,$exp_id);
	my $result = "Sequence\tCharge\tModification\n";
	my %hash;
	while (my ($peptide,$charge,$modification)=$handle->fetchrow_array()){
		$hash{$peptide}{$charge}{$modification} = 1;
	}
	foreach my $peptide(sort {$a cmp $b} keys %hash){
		my %tmp = %{$hash{$peptide}};
		foreach my $charge(sort {$a <=> $b} keys %tmp){
			my %tmp1 = %{$tmp{$charge}};
			foreach my $modification (sort {$a cmp $b} keys %tmp1){
				$result .= "$peptide\t$charge\t$modification\n";
			}
		}
	}
	return "<pre>\n$result</pre>\n";
};

sub getProteinInfo(){
	my $protein = $_[0];
	my $result = "Key\tValue\n";
	my $handle = $dbi->prepare("select id as ID, accession as Accession, description as Description, gene as Gene, gene_id as 'Gene ID' from protein where id=?");
	my $exist = $handle->execute($protein);
	return "" if ($exist==0);
	
	my %hash = %{$handle->fetchrow_hashref()};
	my @keys = ("ID", "Accession", "Description", "Gene", "Gene ID");
	foreach (@keys){
		$result .= "$_\t$hash{$_}\n" if (exists $hash{$_} && (length $hash{$_}>0));
	}
	return $result;
}
#Processed data
##Gets the peptides list for the given experiment. Parameter: experiment id, integers
get '/peptide/list/experiment/:exp_id' => sub {
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	&checkDBI();
	my $handle = $dbi->prepare($peptideAllByExperimentStr);
	$handle->execute($exp_id);
	my $result = "Peptide_ID\tSequence\tProtein\tCharge\tModification\n";
	while (my @arr=$handle->fetchrow_array()){
		my $line = join("\t",@arr);
		$result .= "$line\n";
	}
	return "<pre>\n$result</pre>\n";
};
##Get the peptides list for the given experiment and peptide sequence. Parameter: 1) experiment id, integers; 2) peptide sequence, 20 Amino Acid letters
get '/peptide/list/:sequence/experiment/:exp_id' => sub {
	my $seq = uc(params->{"sequence"});
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $result = &checkPeptide($seq);
	return $result if (length $result > 0);
	&checkDBI();
	my $handle = $dbi->prepare($peptideBySequenceAndExperimentStr);
	$handle->execute($exp_id,$seq);
	$result = "Peptide_ID\tSequence\tProtein\tCharge\tModification\n";
	while (my @arr=$handle->fetchrow_array()){
		my $line = join("\t",@arr);
		$result .= "$line\n";
	}
	return "<pre>\n$result</pre>\n";
};

####The following section is for retrieving quantitative data. The type of values returned is specified by the parameter source which has three pre-defined values: peak (for peak area), observedRT (for observed retention time), and calculatedRT (for calculated retention time)
##Get quantitation values for all peptides within the given run under the given experiment. Parameter: 1) experiment id, integers; 2)run id, integers.
get '/quant/:source/list/experiment/:exp_id/run/:run_id' => sub {
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $run_id = params->{"run_id"};
	unless (&checkIntegers($run_id)) {
		return "Wrong parameter: only numbers allowed for run id";
	}
	my $source = params->{"source"};
	unless ($source eq "peak" || $source eq "observedRT" || $source eq "calculatedRT"){
		return "Unrecognized quantitative data type which currently must be \"peak\", \"observedRT\" or \"calculatedRT\"";
	}
	&checkDBI();
	my $handle = $dbi->prepare($runInfoExperimentStr);
	$handle->execute($run_id,$exp_id);
	my $result = &getQuantitativeData($handle,$source,$exp_id,"ALL");
	return "<pre>\n$result</pre>\n";
};

##Get quantitation values for all peptides under the given experiment. Parameter: experiment id, integers.
get '/quant/:source/list/experiment/:exp_id' => sub {
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $source = params->{"source"};
	unless ($source eq "peak" || $source eq "observedRT" || $source eq "calculatedRT"){
		return "Unrecognized quantitative data type which currently must be \"peak\", \"observedRT\" or \"calculatedRT\"";
	}
	&checkDBI();
	my $handle = $dbi->prepare($runInExperimentStr);
	$handle->execute($exp_id);
	my $result = &getQuantitativeData($handle,$source,$exp_id,"ALL");
	return "<pre>\n$result</pre>\n";
};

##Get quantitation values for all peptides under the given experiment, the given group (regulator code) and the given cell line. Parameter: 1) peptide sequence, 20 Amino Acid letters; 2) experiment id, integers; 3)group name, any existing group name; 4)cell line name, any existing cell lines
get '/quant/:source/list/experiment/:exp_id/group/:group_id' => sub {
	my $exp_id = params->{"exp_id"};
	my $group_id = params->{"group_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $source = params->{"source"};
	unless ($source eq "peak" || $source eq "observedRT" || $source eq "calculatedRT"){
		return "Unrecognized quantitative data type which currently must be \"peak\", \"observedRT\" or \"calculatedRT\"";
	}
	&checkDBI();
	return "The given group $group_id does not exist in the experiment $exp_id, please refer to /run/list/experiment/$exp_id to see all existing groups" if (&checkExistance("group",$exp_id,$group_id)==0);
	my $handle = $dbi->prepare($runByExperiementAndGroupStr);
	$handle->execute($exp_id,$group_id);
	my $result = &getQuantitativeData($handle,$source,$exp_id,"ALL");
	return "<pre>\n$result</pre>\n";
};

##Get quantitation values for all peptides under the given experiment, the given group (regulator code) and the given cell line. Parameter: 1) peptide sequence, 20 Amino Acid letters; 2) experiment id, integers; 3)group name, any existing group name; 4)cell line name, any existing cell lines
get '/quant/:source/list/experiment/:exp_id/cell_line/:cell_line' => sub {
	my $exp_id = params->{"exp_id"};
	my $cell_line = params->{"cell_line"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $source = params->{"source"};
	unless ($source eq "peak" || $source eq "observedRT" || $source eq "calculatedRT"){
		return "Unrecognized quantitative data type which currently must be \"peak\", \"observedRT\" or \"calculatedRT\"";
	}
	&checkDBI();
	return "The given cell line $cell_line does not exist in the experiment $exp_id, please refer to /run/list/experiment/$exp_id to see all used cell lines" if (&checkExistance("cell",$exp_id,$cell_line)==0);
	my $handle = $dbi->prepare($runByExperiementAndCellLineStr);
	$handle->execute($exp_id,$cell_line);
	my $result = &getQuantitativeData($handle,$source,$exp_id,"ALL");
	return "<pre>\n$result</pre>\n";
};

##Get quantitation values for all peptides under the given experiment, the given group (regulator code) and the given cell line. Parameter: 1) peptide sequence, 20 Amino Acid letters; 2) experiment id, integers; 3)group name, any existing group name; 4)cell line name, any existing cell lines
get '/quant/:source/list/experiment/:exp_id/group/:group_id/cell_line/:cell_line' => sub {
	my $exp_id = params->{"exp_id"};
	my $group_id = params->{"group_id"};
	my $cell_line = params->{"cell_line"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $source = params->{"source"};
	unless ($source eq "peak" || $source eq "observedRT" || $source eq "calculatedRT"){
		return "Unrecognized quantitative data type which currently must be \"peak\", \"observedRT\" or \"calculatedRT\"";
	}
	&checkDBI();
	return "The given group $group_id does not exist in the experiment $exp_id, please refer to /run/list/experiment/$exp_id to see all existing groups" if (&checkExistance("group",$exp_id,$group_id)==0);
	return "The given cell line $cell_line does not exist in the experiment $exp_id, please refer to /run/list/experiment/$exp_id to see all used cell lines" if (&checkExistance("cell",$exp_id,$cell_line)==0);
	my $handle = $dbi->prepare($runByExperiementGroupAndCellLineStr);
	$handle->execute($exp_id,$group_id,$cell_line);
	my $result = &getQuantitativeData($handle,$source,$exp_id,"ALL");
	return "<pre>\n$result</pre>\n";
};
##Get quantitation values for all peptides having given sequence under the given experiment and the given run. Parameter: 1) peptide sequence, 20 Amino Acid letters; 2) experiment id, integers; 3) run id, integers.
get '/quant/:source/:sequence/experiment/:exp_id/run/:run_id' => sub {
	my $seq = uc(params->{"sequence"});
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $run_id = params->{"run_id"};
	unless (&checkIntegers($run_id)) {
		return "Wrong parameter: only numbers allowed for run id";
	}
	my $source = params->{"source"};
	unless ($source eq "peak" || $source eq "observedRT" || $source eq "calculatedRT"){
		return "Unrecognized quantitative data type which currently must be \"peak\", \"observedRT\" or \"calculatedRT\"";
	}
	my $result = &checkPeptide($seq);
	return $result if (length $result > 0);
	&checkDBI();
	my $handle = $dbi->prepare($runInfoExperimentStr);
	$handle->execute($run_id,$exp_id);
	$result = &getQuantitativeData($handle,$source,$exp_id,$seq);
	return "<pre>\n$result</pre>\n";
};
##Get quantitation values for all peptides having given sequence under the given experiment. Parameter: 1) peptide sequence, 20 Amino Acid letters; 2) experiment id, integers
get '/quant/:source/:sequence/experiment/:exp_id' => sub {
	my $seq = uc(params->{"sequence"});
	my $exp_id = params->{"exp_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $source = params->{"source"};
	unless ($source eq "peak" || $source eq "observedRT" || $source eq "calculatedRT"){
		return "Unrecognized quantitative data type which currently must be \"peak\", \"observedRT\" or \"calculatedRT\"";
	}
	my $result = &checkPeptide($seq);
	return $result if (length $result > 0);
	&checkDBI();
	my $handle = $dbi->prepare($runInExperimentStr);
	$handle->execute($exp_id);
	$result = &getQuantitativeData($handle,$source,$exp_id,$seq);
	return "<pre>\n$result</pre>\n";
};
##Get quantitation values for all peptides having given sequence under the given experiment and the given group (regulator code). Parameter: 1) peptide sequence, 20 Amino Acid letters; 2) experiment id, integers; 3)group name, anything
get '/quant/:source/:sequence/experiment/:exp_id/group/:group_id' => sub {
	my $seq = uc(params->{"sequence"});
	my $exp_id = params->{"exp_id"};
	my $group_id = params->{"group_id"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $source = params->{"source"};
	unless ($source eq "peak" || $source eq "observedRT" || $source eq "calculatedRT"){
		return "Unrecognized quantitative data type which currently must be \"peak\", \"observedRT\" or \"calculatedRT\"";
	}
	my $result = &checkPeptide($seq);
	return $result if (length $result > 0);
	&checkDBI();
	return "The given group $group_id does not exist in the experiment $exp_id, please refer to /run/list/experiment/$exp_id to see all existing groups" if (&checkExistance("group",$exp_id,$group_id)==0);
	my $handle = $dbi->prepare($runByExperiementAndGroupStr);
	$handle->execute($exp_id,$group_id);
	$result = &getQuantitativeData($handle,$source,$exp_id,$seq);
	return "<pre>\n$result</pre>\n";
};
##Get quantitation values for all peptides having given sequence under the given experiment, and the given cell line. Parameter: 1) peptide sequence, 20 Amino Acid letters; 2) experiment id, integers; 3)cell line name, any existing cell lines
get '/quant/:source/:sequence/experiment/:exp_id/cell_line/:cell_line' => sub {
	my $seq = uc(params->{"sequence"});
	my $exp_id = params->{"exp_id"};
	my $cell_line = params->{"cell_line"};
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $source = params->{"source"};
	unless ($source eq "peak" || $source eq "observedRT" || $source eq "calculatedRT"){
		return "Unrecognized quantitative data type which currently must be \"peak\", \"observedRT\" or \"calculatedRT\"";
	}
	my $result = &checkPeptide($seq);
	return $result if (length $result > 0);
	&checkDBI();
	return "The given cell line $cell_line does not exist in the experiment $exp_id, please refer to /run/list/experiment/$exp_id to see all used cell lines" if (&checkExistance("cell",$exp_id,$cell_line)==0);
	my $handle = $dbi->prepare($runByExperiementAndCellLineStr);
	$handle->execute($exp_id,$cell_line);
	$result = &getQuantitativeData($handle,$source,$exp_id,$seq);
	return "<pre>\n$result</pre>\n";
};
##Get quantitation values for all peptides having given sequence under the given experiment, the given group (regulator code) and the given cell line. Parameter: 1) peptide sequence, 20 Amino Acid letters; 2) experiment id, integers; 3)group name, any existing group name; 4)cell line name, any existing cell lines
get '/quant/:source/:sequence/experiment/:exp_id/group/:group_id/cell_line/:cell_line' => sub {
	my $seq = uc(params->{"sequence"});
	my $exp_id = params->{"exp_id"};
	my $group_id = params->{"group_id"};
	my $cell_line = params->{"cell_line"};
	my $source = params->{"source"};
	unless ($source eq "peak" || $source eq "observedRT" || $source eq "calculatedRT"){
		return "Unrecognized quantitative data type which currently must be \"peak\", \"observedRT\" or \"calculatedRT\"";
	}
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	my $result = &checkPeptide($seq);
	return $result if (length $result > 0);
	&checkDBI();
	return "The given group $group_id does not exist in the experiment $exp_id, please refer to /run/list/experiment/$exp_id to see all existing groups" if (&checkExistance("group",$exp_id,$group_id)==0);
	return "The given cell line $cell_line does not exist in the experiment $exp_id, please refer to /run/list/experiment/$exp_id to see all used cell lines" if (&checkExistance("cell",$exp_id,$cell_line)==0);
	my $handle = $dbi->prepare($runByExperiementGroupAndCellLineStr);
	$handle->execute($exp_id,$group_id,$cell_line);
	$result = &getQuantitativeData($handle,$source,$exp_id,$seq);
	return "<pre>\n$result</pre>\n";
};

####Phosphosite list is the final step of CTAM. As the regulation network could vary among cell lines, we provide two ways to view phosphosite: 1) effects of different regulators on the same peptide 2) under one regulator. The values in the fold change could be Inf (only observed in treatment) or -Inf (only observed in control)
##Get phosphosite list for all peptides with fold change >= 2 or <=0.5 having significance < 0.05 and the given sequence in the given cell line and experiment. Parameters: 1) experiment id, integers; 2) cell line name, any existing cell lines in the experiment; 3) peptide sequence, 20 Amino Acid letters
get '/phosphosite/experiment/:exp_id/cell_line/:cell_line/peptide/:sequence' => sub{
	my $seq = uc(params->{"sequence"});
	my $exp_id = params->{"exp_id"};
	my $cell_line = params->{"cell_line"};
	my $result = &findPhosphositeForPeptide($seq,$exp_id,$cell_line,2,0.05);
	return "<pre>\n$result</pre>\n";
};

##Get phosphosite list with certain fold change for significance < 0.05 and the given sequence in the given cell line and experiment. Parameters: 1) experiment id, integers; 2) cell line name, any existing cell lines in the experiment; 3) peptide sequence, 20 Amino Acid letters; 4) fold change, any numeric value no less than 1, default value is 2 
get '/phosphosite/experiment/:exp_id/cell_line/:cell_line/peptide/:sequence/fold/:fold' => sub{
	my $seq = uc(params->{"sequence"});
	my $exp_id = params->{"exp_id"};
	my $cell_line = params->{"cell_line"};
	my $fold = params->{"fold"};
	my $result = &findPhosphositeForPeptide($seq,$exp_id,$cell_line,$fold,0.05);
	return "<pre>\n$result</pre>\n";
};

##Get phosphosite list with fold change >= 2 or <=0.5 for all peptides having significance < 0.05 and the given sequence in the given cell line and experiment. Parameters: 1) experiment id, integers; 2) cell line name, any existing cell lines in the experiment; 3) peptide sequence, 20 Amino Acid letters; 4) pvalue, the float value less than 1, default value is 0.05 
get '/phosphosite/experiment/:exp_id/cell_line/:cell_line/peptide/:sequence/pvalue/:pvalue' => sub{
	my $seq = uc(params->{"sequence"});
	my $exp_id = params->{"exp_id"};
	my $cell_line = params->{"cell_line"};
	my $pvalue = params->{"pvalue"};
	my $result = &findPhosphositeForPeptide($seq,$exp_id,$cell_line,2,$pvalue);
	return "<pre>\n$result</pre>\n";
};

##Get phosphosite list with certain fold change and pvalue for all peptides having the given sequence in the given cell line and experiment. Parameters: 1) experiment id, integers; 2) cell line name, any existing cell lines in the experiment; 3) peptide sequence, 20 Amino Acid letters; 4) fold change, any numeric value no less than 1, default value is 2; 5) pvalue, the float value less than 1, default value is 0.05 
get '/phosphosite/experiment/:exp_id/cell_line/:cell_line/peptide/:sequence/fold/:fold/pvalue/:pvalue' => sub{
	my $seq = uc(params->{"sequence"});
	my $exp_id = params->{"exp_id"};
	my $cell_line = params->{"cell_line"};
	my $fold = params->{"fold"};
	my $pvalue = params->{"pvalue"};
	my $result = &findPhosphositeForPeptide($seq,$exp_id,$cell_line,$fold,$pvalue);
	return "<pre>\n$result</pre>\n";
};

sub findPhosphositeForPeptide(){
	my ($seq,$exp_id,$cell_line,$fold,$pvalue) = @_;
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	return "Invalid value for fold, default value is 0.05" unless (&checkDoubles($fold));
	return "Invalid value for pvalue, default value is 0.05" unless (&checkDoubles($pvalue));
	return "Value for fold must be no less than 1, default value is 2" if ($fold<1);
	return "Value for pvalue must be no more than 1, default value is 0.05" if ($pvalue > 1);
	my $result = &checkPeptide($seq);
	return $result if (length $result > 0);
	&checkDBI();
	return "The given cell line $cell_line does not exist in the experiment $exp_id, please refer to /run/list/experiment/$exp_id to see all used cell lines" if (&checkExistance("cell",$exp_id,$cell_line)==0);
	my $handle = $dbi->prepare($phosphoByPeptideStr);
	my $controlHandle = $dbi->prepare($identifiedTimesInControlStr);
	my $inverse = 1/$fold;
	$"=">,<";
	$handle->execute($exp_id,$cell_line,$seq,$fold,$inverse,$pvalue);
	$result = "Peptide\tProtein\tCharge\tModification\tPhosphorylation_site\tGroup\tFold_change\tPvalue\tIdentified_times\n";
	while (my ($peptide_id,@arr)=$handle->fetchrow_array()){
		print "Peptide id: $peptide_id\t <@arr>\n";
		$arr[6] =~s/100000000/Inf/;#need to be changed to 100000000
		if ($arr[7] eq "10"){#indicating NA, which is caused by lack of data
			next if ($arr[-1] < 3);
			my $exist = $controlHandle->execute($peptide_id,$exp_id,$cell_line);
			next if ($exist == 0);
			my ($controlCount) = $controlHandle->fetchrow_array();
			next if ($controlCount < 3);
			$arr[7] = "NA";
		}
		my $line = join("\t",@arr);
		$result .= "$line\n";
	}
	return $result;
}

##Get phosphosite list with fold change >= 2 or <=0.5 having significance < 0.05 for all peptides under the given treatment in the given cell line and experiment. Parameters: 1) experiment id, integers; 2) cell line name, any existing cell lines in the experiment; 3) group name, any existing group name
get '/phosphosite/experiment/:exp_id/cell_line/:cell_line/group/:group_id' => sub{
	my $group = uc(params->{"group_id"});
	my $exp_id = params->{"exp_id"};
	my $cell_line = params->{"cell_line"};
	my $result = &findPhosphositeForGroup($exp_id,$group,$cell_line,2,0.05);
	return "<pre>\n$result</pre>\n";
};

##Get phosphosite list with certain fold change having significance < 0.05 for all peptides under the given treatment in the given cell line and experiment. Parameters: 1) experiment id, integers; 2) cell line name, any existing cell lines in the experiment; 3) group name, any existing group name; 4) fold change, any numeric value no less than 1, default value is 2
get '/phosphosite/experiment/:exp_id/cell_line/:cell_line/group/:group_id/fold/:fold' => sub{
	my $group = uc(params->{"group_id"});
	my $exp_id = params->{"exp_id"};
	my $cell_line = params->{"cell_line"};
	my $fold = params->{"fold"};
	my $result = &findPhosphositeForGroup($exp_id,$group,$cell_line,$fold,0.05);
	return "<pre>\n$result</pre>\n";
};

##Get phosphosite list with fold change >= 2 or <=0.5 having significance less than certain pvalue for all peptides under the given treatment in the given cell line and experiment. Parameters: 1) experiment id, integers; 2) cell line name, any existing cell lines in the experiment; 3) group name, any existing group name; 4) pvalue, the float value less than 1, default value is 0.05
get '/phosphosite/experiment/:exp_id/cell_line/:cell_line/group/:group_id/pvalue/:pvalue' => sub{
	my $group = uc(params->{"group_id"});
	my $exp_id = params->{"exp_id"};
	my $cell_line = params->{"cell_line"};
	my $pvalue = params->{"pvalue"};
	my $result = &findPhosphositeForGroup($exp_id,$group,$cell_line,2,$pvalue);
	return "<pre>\n$result</pre>\n";
};

##Get phosphosite list with certain fold change and pvalue for all peptides under the given treatment in the given cell line and experiment. Parameters: 1) experiment id, integers; 2) cell line name, any existing cell lines in the experiment; 3) group name, any existing group name; 4) fold change, any numeric value no less than 1, default value is 2; 5) pvalue, the double value less than 1, default value is 0.05 
get '/phosphosite/experiment/:exp_id/cell_line/:cell_line/group/:group_id/fold/:fold/pvalue/:pvalue' => sub{
	my $group = uc(params->{"group_id"});
	my $exp_id = params->{"exp_id"};
	my $cell_line = params->{"cell_line"};
	my $fold = params->{"fold"};
	my $pvalue = params->{"pvalue"};
	my $result = &findPhosphositeForGroup($exp_id,$group,$cell_line,$fold,$pvalue);
	return "<pre>\n$result</pre>\n";
};

sub findPhosphositeForGroup(){
	my ($exp_id,$group,$cell_line,$fold,$pvalue) = @_;
	return "There are no phosphosites available for the control group, please try another group instead" if (lc($group) eq "control");
	unless (&checkIntegers($exp_id)) {
		return "Wrong parameter: only numbers allowed for experiment id";
	}
	return "Invalid value for fold, default value is 2" unless (&checkDoubles($fold));
	return "Invalid value for pvalue, default value is 0.05" unless (&checkDoubles($pvalue));
	return "Value for pvalue must be no more than 1, default value is 0.05" if ($pvalue > 1);
	return "Value for fold must be no less than 1, default value is 2" if ($fold<1);
	&checkDBI();
	return "The given group $group does not exist in the experiment $exp_id, please refer to /run/list/experiment/$exp_id to see all existing groups" if (&checkExistance("group",$exp_id,$group)==0);
	return "The given cell line $cell_line does not exist in the experiment $exp_id, please refer to /run/list/experiment/$exp_id to see all used cell lines" if (&checkExistance("cell",$exp_id,$cell_line)==0);
	my $handle = $dbi->prepare($phosphoByRegulatorStr);
	my $controlHandle = $dbi->prepare($identifiedTimesInControlStr);
	my $inverse = 1/$fold;
	$handle->execute($exp_id,$cell_line,$group,$fold,$inverse,$pvalue);
	my $result = "Peptide\tProtein\tCharge\tModification\tPhosphorylation_site\tGroup\tFold_change\tPvalue\tIdentified_times\n";
	while (my ($peptide_id,@arr)=$handle->fetchrow_array()){
		$arr[6] =~s/100000000/Inf/;#need to be changed to 100000000
		if ($arr[7] eq "10"){
			next if ($arr[-1] < 3);
			my $exist = $controlHandle->execute($peptide_id,$exp_id,$cell_line);
			next if ($exist == 0);
			my ($controlCount) = $controlHandle->fetchrow_array();
			next if ($controlCount < 3);
			$arr[7] = "NA";
		}
		my $line = join("\t",@arr);
		$result .= "$line\n";
	}
	return $result;
}

sub getQuantitativeData(){
	my $handle = $_[0]; #the handle to get run names and ids
	my $source = $_[1]; #table source: peak, calculated rt or observed rt
	my $exp_id = $_[2]; #experiment id
	my $type = $_[3]; #all peptide (value as "ALL") or given peptide (value as peptide sequence)
	my @run_ids;
	my @run_names;
	while(my ($run_id,$name)=$handle->fetchrow_array()){
		push (@run_ids, $run_id);
		push (@run_names,$name);
	}
	return &getValuesForPeptides($type,$source,$exp_id,\@run_ids,\@run_names);
}

# Check the connection is alive
sub checkDBI(){
#	$dbi = &getDBI("localhost") unless (defined $dbi);#subroutine from misc.pl which generates database handle according to the setting profile
#	return;
    if ($dbi->{Active}) { 
        my $result = eval { $dbi->ping };

        if ($@){
        	$dbi = &getDBI("localhost");
        	return;
        }

	    if (int($result)) {
            # DB driver itself claims all is OK, trust it:
            return ;
        } else {
            # It was "0 but true", meaning the default DBI ping implementation
            # Implement our own basic check, by performing a real simple query.
            my $ok;
            eval {
                $ok = $dbi->do('select 1');
            };
            unless ($ok){
            	$dbi = &getDBI("localhost");
            	return;
            }
        }
    } else {
        $dbi = &getDBI("localhost");
    }
}

sub checkExistance(){
	my ($type,$exp_id,$entity)=@_;
	&checkDBI();
	my $sql = $groupExistanceStr;
	$sql = $cellExistanceStr if ($type eq "cell");
	my $handle = $dbi->prepare($sql);
	my $count = $handle->execute($exp_id,$entity);
	return $count;
}

sub checkIntegers(){
	my $arg = $_[0];
	if ($arg=~/^\d+$/){
		return true;
	}
	return false;
}

sub checkDoubles(){
	my $arg = $_[0];
	if($arg=~/^\d+(\.\d+)?/){
		return true;
	}
	return false;
}

sub checkPeptide(){
	my $pep = $_[0];
	if($pep=~/[^ARNDCEQGHILKMFPSTWYV]/){
		return "Only 20 natural amino acids are accepted, found $& in the given sequence";
	}elsif((length $pep)<4){
		return "Given sequence is too short, need to be no less than four AAs";
	}
	return "";
}

sub getValuesForPeptides(){
	my ($seq,$source,$exp_id,$id_ref,$name_ref) = @_;
	my $result = "Sequence\tProtein\tCharge\tModification";
	#get runs
	my @run_ids = @{$id_ref};
	my @names = @{$name_ref};
	foreach my $name(@names){
		$result .= "\t$name";
	}
	$result .="\n";
	my $handle;
	if ($seq eq "ALL"){
		$handle = $dbi->prepare($peptideAllByExperimentStr);
		$handle->execute($exp_id);
	}else{
		$handle = $dbi->prepare($peptideBySequenceAndExperimentStr);
		$handle->execute($exp_id,$seq);
	}
	my $quantByPeptideAndExperimentStr = "select run_id, value from ";
	if($source eq "peak"){
		$quantByPeptideAndExperimentStr .= "peak_area";
	}elsif($source eq "observedRT"){
		$quantByPeptideAndExperimentStr .= "observed_RT";
	}else{
		$quantByPeptideAndExperimentStr .= "calculated_RT";
	}
	$quantByPeptideAndExperimentStr .= " where peptide_id = ? and experiment_id = ?";
	my $valueHandle = $dbi->prepare($quantByPeptideAndExperimentStr);
	while (my @arr=$handle->fetchrow_array()){#for each peptide
		my $peptide_id = shift @arr;
		my $peptide_info = join("\t",@arr);
		$result.="$peptide_info";
		$valueHandle->execute($peptide_id,$exp_id);
		my %values;
		while (my ($run_id,$value) = $valueHandle->fetchrow_array()){
			$values{$run_id}=$value;
		}
		foreach my $run_id(@run_ids){
			if (exists($values{$run_id})){
				$result.="\t$values{$run_id}";
			}else{
				$result.="\t0";
			}
		}
		$result.="\n";
	}
	return $result;
}
true;
