#this script reads in the peak area data for a given experiment, do statistical analyses and output the result as CSV file
#which will be proecessed by another script to import into database
library("hash")
library("preprocessCore")
library("RCurl")

baseURL <- "http://ctamdb.sbcs.qmul.ac.uk/"
#baseURL <- "http://localhost:5000/"
#generates the link for retrieving peak area data based on experiment id, group and cell line 
generatePeakQueryString<-function(exp_id,group,cell_line){
	link<-paste(baseURL,"quant/peak/list/experiment/",sep="")
	link<-paste(link,exp_id,sep="")
	link<-paste(link,"/group/",sep="")
	link<-paste(link,group,sep="")
	link<-paste(link,"/cell_line/",sep="")
	link<-paste(link,cell_line,sep="")
	return (link)
}
#peptide uniqueness is based on the combination of its sequence, protein, charge and modification 
generateIndex<-function(pep,pro,charge,mod){
	index<-paste(pep,pro,sep=";")
	index<-paste(index,charge,sep=";")
	index<-paste(index,mod,sep=";")
	return (index)
}
#replace 0 and NA with one-tenth of minimum value of the column, then divide by sum, finishing with multiplying 1e+7
columnNormalization<-function(x){
	x[x==NA]<-0
	#direct min(x) will return 0
	tmp.max.value<-10^(ceiling(log10(max(x)))+1)
	x[x==0]<-tmp.max.value
	min.value<-min(x)/10
	x[x==tmp.max.value]<-min.value
	return (x/sum(x)*1000000)
}
#note only one outlier per line is replaced with median of the vector after removing the outlier
detectOutliers<-function(x){
	mean<-mean(x)
	sd<-sd(x)
	cv<-sd/mean
	max.value<-0
	idx<-0
	val<-abs(log10(mean))
	for(i in 1:length(x)){
		curr <- 10
		if (x[i]>0){
			curr <- log10(x[i])
		}
		diff <- abs(val - curr)
		if (diff > max.value){
			max.value <- diff
			idx <- i
		}
	}
	x.new <- x[-idx] #remove the outlier to form a new array
	median <- median(x.new)
	x[idx] <-median
	return (x)
}
#Handles the error message while connecting to the API server
errorForNetworking<-function(e){
	if (e$message=="cannot open the connection"){
		print (paste("Cannot make connection to ",runs_links,sep=""))
	}else{
		print (paste("Error:",e$message,sep=""))
	}
	q()	
}
#Handles the warning message while connecting to the API server
warningForNetworking<-function(w){
	idx<-regexpr("incomplete final line",w$message,fixed=TRUE)
	if(idx>-1){
		print (paste("The given experiment id "," does not exist",sep=args[1]))
	}else{
		idx<-regexpr("be resolved",w$message,fixed=TRUE)
		if(idx>-1){
			print(paste("Cannot resolve the link ",baseURL,sep=""))
		}else{
			print (paste("Warning:",w$message,sep=""))
		}
	}
	q()
}

#constant value setting
control<-"control";
#parse the command line parameters
args <- commandArgs(trailingOnly = TRUE)
#check the number of parameters which should be between 1 and 3
args.length <- length(args)
if(args.length < 1 || args.length > 2){
	print ("Wrong parameter number which can only be 1 or 2")
	print ("Usage: RScript 'ctam statistics.r' <experiment id> [normalization method choice]")
	print ("experiment id is a positive integer value and normalization method choice can be either quantile(default) or column(Pedro's way)")
	q()
}

tryCatch(exp_id <- as.numeric(args[1]),warning = function(w){
	print (paste("given experiment id "," is not numeric",sep=args[1]))
	q()
})

#experiment id must be a positive integer
if((exp_id%%1)!=0 || exp_id<=0){
	print ("experiment id should be a positive integer")
	q()
}

method <- "quantile"
if (args.length == 2){
	if(args[2]!="quantile" && args[2]!="column"){
		print ("The allowed value for 'normalization method choice' only can be either quantile(default) or column(Pedro's way)")
		q()
	}
	method <- args[2]
}
#
msg <- paste("Dealing with experiment ",exp_id,sep="")
msg <- paste(msg,method,sep=" with method ")
print (msg)

#get all runs for the given experiment
runs_links<-paste(baseURL,"run/list/experiment/",sep="")
runs_links<-paste(runs_links,exp_id,sep="")
print(runs_links)
#stringsAsFactors is default on TRUE, which converts any text to a factor
#read.delim(runs_links,comment.char="<")
tryCatch(runs <- read.delim(runs_links,comment.char="<"), 
	error=function(e){errorForNetworking(e)}, 
	warning=function(w){warningForNetworking(w)}
)

#get all unique combination of group (treatment) and cell line
runs$combined <- paste(runs$Group,runs$Cell_line,sep=";")
combined<-as.factor(runs$combined)
combination<-levels(combined) #typeof: character

controls_cell_lines<-hash() #store control values
treatment<-hash() #store treatment values

#get data from database, pre-process and save into control and treatment hashes
#Pre-processing based on a pure data matrix with peptides as rows and runs as columns
i<-0;
for (entry in combination){
	i<-i+1
#	entry<-"PF4708671;MCF-7" #debug purpose
	msg<-paste("Set ",i," :Now downloading data for ",entry,sep="")
	print (msg)
	print (Sys.time())
	#read peak values from CTAM database
	#generate the link for the peak
	elem<-strsplit(entry,";",fixed=TRUE)[[1]]#strsplit returns a list
	group<-elem[1]
	cell<-elem[2]
	link<-generatePeakQueryString(exp_id,group,cell)#generate the link to retrieve peak area data
	print(link)
	#convert to data frame as matrix only supports one type of data while in this case there are strings (peptide) and numeric (peak value)
#	df<-as.data.frame(read.delim(link,comment.char="<"))#colclasses can be applied here, but no prior knowledge how many columns it will be, so choose using extra as.numeric step
	#direct use may encounter timeout, refers to http://stackoverflow.com/questions/27698754/request-url-failed-timeout-in-r
	myOpts <- curlOptions(connecttimeout = 300)
	urlTSV<-getURL(link,.opts = myOpts)
	txtTSV<-textConnection(urlTSV)
	df<-as.data.frame(read.delim(txtTSV,comment.char="<"))
	#get column count
	colNum<-dim(df)[2]
	if(colNum<6){#only one data column in the group which is impossible according to the experiment design
		print (paste("Not sufficient data columns for ",entry,sep=""))
		combination <- combination[combination != entry] #drop this entry as no data available for processing
		next
	}
	#extract peptide info part
	info<-df[,1:4] #peptide, protein, charge, modification
	#and value part
	data<-as.matrix(df[,5:colNum])#normalize.quantiles only takes matrix
	#get the descriptive statistics: mean, count of non-0
#1.	Make a copy of the original matrix and replaced 0 with NA
	data1<-data
	data1[data1==0]<-NA
#2.	Record how many values are not NA (not 0) in each row
	count<-apply(data1,1,function(x){return (sum(!is.na(x)))}) #one of alternative methods is length(na.omit(v))
#3.	Calculate the mean of original peak values for each row ignoring NA
	meanOrigin <- rowMeans(data1, na.rm=TRUE)#only calculate average peak while ignoring 0

	#store the mean of original peak value, particularly for the 0 which indicates peptide not existing
	header<-colnames(data)#normalize.quantiles removes the header, so save a copy
	header<-c(header,"sd","meanOrigin","count")

#4.	Apply normalization 

	#normalization comment out either of those two methods 
	if(method == "column"){
	#	data<-t(t(data)/rowSums(t(data)))
		data.normalized<-apply(data,2,columnNormalization)
		data.normalized[is.nan(data.normalized)]<-0#replace NaN with 0 which could happen when one whole column is 0
		#remove the outlier
		data.outlier<-t(apply(data.normalized,1,detectOutliers))#after apply row calculation, needs to be transpose to column again
		data<-data.outlier
	}else{
		data<-normalize.quantiles(data)
	}

#5.	Replace value 0 with 1
	#replace 0 with 1 which will become to 0 during log2 calculation, 0 would be -Inf then no sd
	data[data==0]<-1
#6.	Log2 transformation which turns value of 1 into 0
	data<-log2(data)
#7.	Replace log2 value of 0 with NA
	data[data==0]<-NA
#8.	Calculate SD
	#add row sd, rowSds available from library(matrixStats)
	data<-cbind(data,apply(data,1,sd,na.rm = TRUE),meanOrigin,count)

	#add header back
	colnames(data)<-header

	#merge info and data parts back
	values<-data.frame();
	#combine string values from four columns into one to serve as index string which make it possible to search within one column instead of four columns
	indice<-apply(info,1,function(x){return (generateIndex(x[1],x[2],x[3],x[4]))})
	#now values should have (colNum+4) columns 
	#first 4 columns for information, 5th column as indice, last 3 columns are sd, meanOrigin, count, and the middle are the log2 normalized data
	values<-cbind(info,indice,data)

	#if from control group, save into a special hash for later student t-test
	if (group == control){
		controls_cell_lines[[cell]]<-values# [[ instead of $ as $ uses cell_line as the key
	}else{
		treatment[[entry]]<-values
	}
}
#pre-processing finishes

#onlyList stores the peptide only detected in control (not in treatment) or only in treatment (not in control)
#which can NOT be applied Ttest
#the column names of middle list among which index column is only kept there to copy adjusted p value over and will be removed
column_names <- c("Experiment","Group","Cell line","Peptide","Protein","Charge","Modification","index","fold change", "pvalue", "adjusted pvalue","Control mean","Control count","Treatment mean","Treatment count")
result.final<-data.frame(matrix(vector(),0,15,dimnames=list(c(),column_names)))
index_loc<-which(column_names=="index")
#stores the peptide list with adjusted p value less than 0.05
#for each entry in treatment hash, compare to corresponding control
i<-0
for (entry in keys(treatment)){
#	significantList<-data.frame(matrix(vector(),0,2,dimnames=list(c(),c("index","pvalue"))))
	i<-i+1
	pvalues<-c()
	rowIndice<-c()
	result.middle<-data.frame(matrix(vector(),0,15,dimnames=list(c(),column_names)))
	msg<-paste("Set ",i," :Now processing data for ",entry,sep="")
	print (msg)
	print (Sys.time())
	elem<-strsplit(entry,";",fixed=TRUE)[[1]]#strsplit returns a list
#1.	Locates the corresponding row in the control data
#2.	Based on number of non-NA (i.e. non-zero peak value from Pescal++)
#	a.	0 (i.e. no peak detected): If number of non-NA in control is
#		i.	0 (no change): fold change recorded as NA, pvalue recorded as NA
#		ii.	>0 (inhibitor inhibits the peptide): fold change recorded as –Inf, pvalue recorded as NA
#	b.	1 (i.e. only one peak detected, no t-test can be applied): If number of non-NA in control is 
#		i.	0 (not found in control): fold change recorded as Inf, pvalue recorded as NA
#		ii.	>0: fold change recorded as mean of treatment/mean of control, pvalue recorded as NA
#	c.	>1 (t test may be able to be applied): If number of non-NA in control is
#		i.	0 (not found in control): fold change recorded as Inf, pvalue recorded as NA
#		ii.	1: fold change recorded as mean of treatment/mean of control, pvalue recorded as NA
#		iii.	>1: Based on the sd values of both treatment and control
#			1.	Both sd values are 0 (no variance at all): which leads the denominator to be equal to 0, therefore fold change recorded as mean of treatment/mean of control, pvalue recorded as NA
#			2.	Otherwise: two sample t-test applied, fold change recorded as 2 to the power of mean difference and pvalue extracted from t-test
#Apply BH correction on all non-NA pvalues
	group<-elem[1]
	cell<-elem[2]
	if(!has.key(cell,controls_cell_lines)){
		print (paste("No corresponding control data found for ",entry,sep=""))
		next;
	}
	#get current treatment data
	values.treatment<-treatment[[entry]]
	#get corresponding control data
	values.control<-controls_cell_lines[[cell]]
	#treatment may have different numbers of repeat to the control
	colNum.treatment <- dim(values.treatment)[2]
	colNum.control <- dim(values.control)[2]
	#for each row in treatment data
	for (rowIndex in 1:dim(values.treatment)[1]){
		oneRow<-c(exp_id,group,cell,values.treatment[rowIndex,1:5])
		index<-values.treatment$indice[rowIndex]
		#find corresponding row in control
		#in most case the control and treatment data should have the same order
		#therefore check it first, if not matching, search the index string instead
		if(values.control$indice[rowIndex]==index){
			rowIndex.control<-rowIndex
		}else{
			rowIndex.control<-which(values.control[,"indice"]==index)
		}
#2.	Based on number of non-NA (i.e. non-zero peak value from Pescal++) in treatment
#	a.	0 (i.e. no peak detected): If number of non-NA in control is
#		i.	0 (no change): fold change recorded as NA, pvalue recorded as NA
#		ii.	>0 (inhibitor inhibits the peptide): fold change recorded as –Inf, pvalue recorded as NA
		if(values.treatment$count[rowIndex]==0){
#			print ("treatment 0")
			if(values.control$count[rowIndex.control]==0){
#				print ("treatment 0 control 0")
				foldchange <- NA
			}else{
#				print ("treatment 0 control other")
				foldchange <- -Inf
			}
			pvalue <- NA
#	b.	1 (i.e. only one peak detected, no t-test can be applied): If number of non-NA in control is 
#		i.	0 (not found in control): fold change recorded as Inf, pvalue recorded as NA
#		ii.	>0: fold change recorded as mean of treatment/mean of control, pvalue recorded as NA
		}else if(values.treatment$count[rowIndex]==1){
#			print ("treatment 1")
			if(values.control$count[rowIndex.control]==0){
#				print ("treatment 1 control 0")
				foldchange <- Inf
			}else{
#				print ("treatment 1 control other")
				foldchange <- values.treatment$meanOrigin[rowIndex]/values.control$meanOrigin[rowIndex.control] 
			}
			pvalue <- NA
#	c.	>1 (t test may be able to be applied): If number of non-NA in control is
#		i.	0 (not found in control): fold change recorded as Inf, pvalue recorded as NA
#		ii.	1: fold change recorded as mean of treatment/mean of control, pvalue recorded as NA
#		iii.	>1: Based on the sd values of both treatment and control
#			1.	Both sd values are 0 (no variance at all): which leads the denominator to be equal to 0, therefore fold change recorded as mean of treatment/mean of control, pvalue recorded as NA
#			2.	Otherwise: two sample t-test applied, fold change recorded as 2 to the power of mean difference and pvalue extracted from t-test
		}else{#treatment > 1
#			print ("treatment other")
			if(values.control$count[rowIndex.control]==0){
#				print ("treatment other control 0")
				foldchange <- Inf
				pvalue <- NA
			}else if(values.control$count[rowIndex.control]==1){
#				print ("treatment other control 1")
				foldchange <- values.treatment$meanOrigin[rowIndex]/values.control$meanOrigin[rowIndex.control] 
				pvalue <- NA
			}else{
#				print ("treatment other control other")
				if(values.control$sd[rowIndex.control]==0 && values.treatment$sd[rowIndex]==0){#when both sd = 0, i.e. constant vector, t test cannot be done
#					print ("both SD 0")
					foldchange <- values.treatment$meanOrigin[rowIndex]/values.control$meanOrigin[rowIndex.control] 
					pvalue<-NA
				}else{
#					print ("not both SD 0")
					data.treatment<-values.treatment[rowIndex,6:(colNum.treatment-3)]#one extra column indice (column 5) was inserted, therefore last column index become colNum+1 and data start from 6 instead of 5
					data.control<-values.control[rowIndex.control,6:(colNum.control-3)]
					ttest<-t.test(data.treatment,data.control)
					pvalue<-ttest$p.value
					foldchange <- values.treatment$meanOrigin[rowIndex]/values.control$meanOrigin[rowIndex.control]
#					vec<-c(toString(index),pvalue)
#					names(vec)<-c("index","pvalue")
#					vec<-as.data.frame(vec)
#					significantList<-rbind(significantList,vec)
					pvalues<-append(pvalues,pvalue)
					rowIndice<-append(rowIndice,rowIndex)
				}
			}
		}
		oneRow<-c(oneRow,foldchange,pvalue,NA)
		oneRow<-c(oneRow,values.control$meanOrigin[rowIndex.control],values.control$count[rowIndex.control])
		oneRow<-c(oneRow,values.treatment$meanOrigin[rowIndex],values.treatment$count[rowIndex])
		names(oneRow)<-column_names
		oneRow<-as.data.frame(oneRow)#this conversion is because the column names containing space which in data frame will be replaced with .=>mismatch column names cell line vs cell.line
		result.middle<-rbind(result.middle,oneRow)
	}

	if (length(pvalues)>0){
		pvalues.adjust <- p.adjust(pvalues, method = 'hochberg', n = length(pvalues))
		significantList<-data.frame(serial=rowIndice,pvalues=pvalues.adjust)
		#replace the pvalue in result.middle with the adjusted pvalues using index
		for (i in 1:nrow(significantList)){
			rowIndex<-significantList$serial[i]
			pvalue.adjust<-significantList$pvalues[i]
			result.middle$adjusted.pvalue[rowIndex]<-pvalue.adjust
		}
	}

	result.removed<-result.middle[,-index_loc]
	#add this middle result to the final result
	result.final<-rbind(result.final,result.removed)
}

filename<-paste("statistical_result_using_",method,sep="")
filename<-paste(filename,exp_id,sep="_experiment_")
filename<-paste(filename,".csv",sep="")
print (paste("Saving to the result file ",filename,sep=""))
write.csv(result.final, file=filename, row.names = FALSE)

