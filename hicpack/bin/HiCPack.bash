#!/bin/bash

## HiCPack
## Author(s): Mohsen Naghipourfar
## Contact: mn7697np@gmail.com or naghipourfar@ce.sharif.edu
## This software is distributed without any guarantee under the terms of the GNU General
## MIT License


SOFT="HiCPack"
VERSION="1.0.10"

function usage {
    echo -e "usage : $SOFT -i INPUT -o OUTPUT -c CONFIG [-s ANALYSIS_STEP]"
    echo -e "Use option -h|--help for more information"
}

function help {
    usage;
    echo
    echo "$SOFT $VERSION"
    echo "---------------"
    echo "OPTIONS"
    echo
    echo "   -i|--input INPUT : input data folder; Must contains a folder per sample with input files"
    echo "   -o|--output OUTPUT : output folder"
    echo "   -c|--conf CONFIG : configuration file for Hi-C processing"
    echo "   -r|--sra SRA_NUMBER : SRR number to fetch for Hi-C processing"
    echo "   [-p|--parallel] : if specified run $SOFT on a cluster"
    echo "   [-s|--step ANALYSIS_STEP] : run only a subset of the $SOFT workflow; if not specified the complete workflow is run"
    echo "      mapping: perform reads alignment - require fast files"
    echo "      proc_hic: perform Hi-C filtering - require BAM files"
    echo "      quality_checks: run Hi-C quality control plots"
    echo "   [-h|--help]: help"
    echo "   [-v|--version]: version"
    exit;
}

function version {
    echo -e "$SOFT version $VERSION"
    exit
}

function opts_error {
    echo -e "Error : invalid parameters !" >&2
    echo -e "Use $SOFT -h for help"
    exit
}

## Set PATHS
BIN_PATH=`dirname $0`
ABS_BIN_PATH=`cd "$BIN_PATH"; pwd`
SCRIPTS_PATH="$ABS_BIN_PATH/../scripts/"
INSTALL_PATH="$ABS_BIN_PATH/../"
CUR_PATH=$PWD

CLUSTER=0
MAKE_OPTS=""
INPUT=""
OUTPUT=""
CONF=""

#####################
## Inputs
#####################
if [ $# -lt 1 ]
then
    usage
    exit
fi

# Transform long options to short ones
for arg in "$@"; do
  shift
  case "$arg" in
      "--input") set -- "$@" "-i" ;;
      "--output") set -- "$@" "-o" ;;
      "--conf")   set -- "$@" "-c" ;;
      "--step")   set -- "$@" "-s" ;;
      "--sra")   set -- "$@" "-r" ;;
      "--parallel")   set -- "$@" "-p" ;;
      "--help")   set -- "$@" "-h" ;;
      "--version")   set -- "$@" "-v" ;;
      *)        set -- "$@" "$arg"
  esac
done

while getopts ":i:o:c:s:r:pvh" OPT
do
    case $OPT in
	i) INPUT=$OPTARG;;
	o) OUTPUT=$OPTARG;;
	c) CONF=$OPTARG;;
	s) MAKE_OPTS="$MAKE_OPTS $OPTARG";;
	r) SRA_NUMBER="$OPTARG";;
	p) CLUSTER=1 ;;
	v) version ;;
	h) help ;;
	\?)
	     echo "Invalid option: -$OPTARG" >&2
	     usage
	     exit 1
	     ;;
	 :)
	     echo "Option -$OPTARG requires an argument." >&2
	     usage
	     exit 1
	     ;;
    esac
done

if [[ ! -e ${INSTALL_PATH}/config-system.txt ]]; then
    echo "Error - Installation - config system not detected. Please (re)install HiCPack !"
    exit -1
fi


if [[ -z $INPUT || -z $OUTPUT || -z $CONF ]]; then
    usage
    exit
fi


#####################
## Check Config file
#####################
## Read conf file
. ${SCRIPTS_PATH}/hic.inc.sh

INPUT=`abspath $INPUT`
OUTPUT=`abspath $OUTPUT`

if [[ ! -e ${INPUT} ]]; then
    echo "Inputs '$INPUT' not found. Exit."
    exit -1
fi

if [[ -z $PAIR1_EXT || -z $PAIR2_EXT ]]; then
    die "Read pairs extensions not defined. Exit"
fi

if [[ $(echo ${REFERENCE_GENOME} | grep -c -e ${PAIR1_EXT} -e ${PAIR2_EXT}) == "1" ]]; then
    die "Conflict in file names. PAIR1_EXT/PAIR2_EXT detected in REFERENCE_GENOME. Please correct before running. Exit"
fi


GENOME_SIZE_FILE=`abspath $GENOME_SIZE`
if [[ ! -e ${GENOME_SIZE_FILE} ]]; then
    GENOME_SIZE_FILE=$ANNOT_DIR/$GENOME_SIZE
fi

GENOME_FRAGMENT_FILE=`abspath $GENOME_FRAGMENT`
if [[ ! -e $GENOME_FRAGMENT_FILE ]]; then
    GENOME_FRAGMENT_FILE=$ANNOT_DIR/$GENOME_FRAGMENT
fi

## check other annotation files
if [[ ! -z $GENOME_SIZE_FILE && ! -e $GENOME_SIZE_FILE ]]; then
    die "GENOME_FILE $GENOME_SIZE_FILE not found. Exit"
fi

if [[ ! -z $GENOME_FRAGMENT_FILE && ! -e $GENOME_FRAGMENT_FILE ]]; then
    die "GENOME_FRAGMENT $GENOME_FRAGMENT_FILE not found. Exit"
fi
echo "BOWTIE2_INDEX_PATH is $BOWTIE2_IDX_PATH"
if [[ ! -z $BOWTIE2_IDX_PATH && ! -d $BOWTIE2_IDX_PATH ]]; then
    die "BOWTIE2_IDX $BOWTIE2_IDX_PATH directory not found. Exit"
fi

if [[ ! -z $CAPTURE_TARGET && ! -e $CAPTURE_TARGET ]]; then
    die "CAPTURE_TARGET $CAPTURE_TARGET not found. Exit"
fi

if [[ ! -z $ALLELE_SPECIFIC_SNP && ! -e $ALLELE_SPECIFIC_SNP ]]; then
    die "ALLELE_SPECIFIC_SNP $ALLELE_SPECIFIC_SNP not found. Exit"
fi


#####################
## Check step option
#####################

MAKE_OPTS=$(echo $MAKE_OPTS | sed -e 's/^ //')
AVAILABLE_STEP_ARRAY=("mapping" "proc_hic" "quality_checks" "merge_persample" "build_contact_maps" "bg_model" "visualization" "tad_calling" "fetch_data")
NEED_BAM_STEP_ARRAY=("proc_hic")
NEED_VALID_STEP_ARRAY=("merge_persample")
NEED_ALLVALID_STEP_ARRAY=("build_contact_maps")
NEED_MAT_STEP_ARRAY=("bg_model" "visualization" "tad_calling")
NEED_FASTQ_STEP_ARRAY=("mapping")
NEED_ANY_STEP_ARRAY=("quality_checks")
NEED_ANY_SRA_NUMBERS=("fetch_data")


NEED_BAM=0
NEED_VALID=0
NEED_ALLVALID=0
NEED_MAT=0
NEED_FASTQ=0
NEED_ANY=0
NEED_SRA=0


if [[ $MAKE_OPTS != "" ]]; then
    for s in $MAKE_OPTS
    do
        check_s=0
        for i in ${AVAILABLE_STEP_ARRAY[@]}; do
            if [[ "$i" == "$s" ]]; then check_s=1; fi
        done
        if [[ $check_s == 0 ]]; then die "Unknown step option (\"-s $s\"). Use $0 --help for usage information."; fi

        for i in ${NEED_BAM_STEP_ARRAY[@]}; do
            if [[ "$i" == "$s" ]]; then NEED_BAM=1; fi
        done

        for i in ${NEED_VALID_STEP_ARRAY[@]}; do
            if [[ "$i" == "$s" ]]; then NEED_VALID=1; fi
        done

        for i in ${NEED_ALLVALID_STEP_ARRAY[@]}; do
            if [[ "$i" == "$s" ]]; then NEED_ALLVALID=1; fi
        done

        for i in ${NEED_MAT_STEP_ARRAY[@]}; do
            if [[ "$i" == "$s" ]]; then NEED_MAT=1; fi
        done

        for i in ${NEED_FASTQ_STEP_ARRAY[@]}; do
            if [[ "$i" == "$s" ]]; then NEED_FASTQ=1; fi
        done

        for i in ${NEED_ANY_STEP_ARRAY[@]}; do
            if [[ "$i" == "$s" ]]; then NEED_ANY=1; fi
        done

        for i in ${NEED_ANY_SRA_NUMBERS[@]}; do
            if [[ "$i" == "$s" ]]; then NEED_SRA=1; fi
        done
    done
else
    NEED_FASTQ=1
fi

#####################
## Check data structure
#####################

## Check rawdata structure
if [[ $NEED_SRA  == 1 ]]; then
    exec_cmd "${SRATOOLKIT_PATH}/fastq-dump $SRA_NUMBER -I --split-files --outdir ${INPUT}/${SRA_NUMBER}/"
    NEED_FASTQ=1
fi

if [[ $NEED_FASTQ == 1 ]]; then
    nbin=$(find -L $INPUT -mindepth 2 -maxdepth 2 -name "*.fastq" -o -name "*.fastq.gz" | wc -l)
    nbin_r1=$(find -L $INPUT -mindepth 2 -maxdepth 2 -name "*.fastq*" -and -name "*${PAIR1_EXT}*" | wc -l)
    nbin_r2=$(find -L $INPUT -mindepth 2 -maxdepth 2 -name "*.fastq*" -and -name "*${PAIR2_EXT}*" | wc -l)
    if [ $nbin == 0 ]; then
	die "Error: Directory Hierarchy of rawdata '$INPUT' is not correct. No '.fastq(.gz)' files detected"
    fi
    if [[ $nbin_r1 == 0 || $nbin_r2 == 0 || $nbin_r1 != $nbin_r2 ]]; then
        die "Error: Directory Hierarchy of rawdata '$INPUT' is not correct. Paired '.fastq' files with ${PAIR1_EXT}/${PAIR2_EXT} are required !"
    fi

elif [[ $NEED_BAM == 1 ]]; then
    nbin=$(find -L $INPUT -mindepth 2 -maxdepth 4 -name "*.bam" | wc -l)
    nbin_r1=$(find -L $INPUT -mindepth 2 -maxdepth 4 -name "*.bam" -and -name "*${PAIR1_EXT}* | wc -l")
    nbin_r2=$(find -L $INPUT -mindepth 2 -maxdepth 4 -name "*.bam" -and -name "*${PAIR2_EXT}* | wc -l")
    if [[ $nbin == 0 || $nbin_r1 != $nbin_r2 ]]; then
	die "Error: Directory Hierarchy of rawdata '$INPUT' is not correct. Paired '.bam' files with ${PAIR1_EXT}/${PAIR2_EXT} are required for '$MAKE_OPTS' step(s)"
    fi
elif [[ $NEED_VALID == 1 ]]; then
    nbin=$(find -L $INPUT -mindepth 2 -maxdepth 6 -name "*.validPairs" | wc -l)
    if [ $nbin == 0 ]; then
        die "Error: Directory Hierarchy of rawdata '$INPUT' is not correct. No '.validPairs' files detected"
    fi
elif [[ $NEED_ALLVALID == 1 ]]; then
    nbin=$(find -L $INPUT -mindepth 2 -maxdepth 6 -name "*.allValidPairs" | wc -l)
    if [ $nbin == 0 ]; then
        die "Error: Directory Hierarchy of rawdata '$INPUT' is not correct. No '.allValidPairs' files detected"
    fi
elif [[ $NEED_MAT == 1 ]]; then
    nbin=$(find -L $INPUT -mindepth 1 -maxdepth 6 -name "*.matrix" | wc -l)
    if [ $nbin == 0 ]; then
        die "Error: Directory Hierarchy of rawdata '$INPUT' is not correct. No '.matrix' files detected"
    fi
else
    if [[ $NEED_ANY == 0 ]]; then
    	die "Error: unknown type for input files"
    fi
fi

#####################
## Init HiCPack
####################
if [[ -d $OUTPUT && $MAKE_OPTS == "" ]]; then
    echo "$OUTPUT folder alreads exists. Do you want to overwrite it ? (y/n) [n] : "
    read ans
    if [ XX${ans} = XXy ]; then
	/bin/rm -rf $OUTPUT
    elif [ XX${ans} = XXn ]; then
	exit -1
    fi
fi
mkdir -p $OUTPUT

if [ -L $OUTPUT/$RAW_DIR ]; then
    /bin/rm $OUTPUT/$RAW_DIR
fi
ln -s $INPUT $OUTPUT/$RAW_DIR

## cp config file in output
#if [ ! -e ${OUTPUT}/$(basename ${CONF}) ]; then
cp $CONF ${OUTPUT}/$(basename ${CONF})
#fi

cd $OUTPUT

#######################
## Check input files ##
#######################

if [[ $NEED_FASTQ == 1 ]]; then
    r1files=$(find -L ${RAW_DIR} -mindepth 2 -maxdepth 2 -name "*.fastq" -o -name "*.fastq.gz" | grep "$PAIR1_EXT" | wc -l)
    r2files=$(find -L ${RAW_DIR} -mindepth 2 -maxdepth 2 -name "*.fastq" -o -name "*.fastq.gz" | grep "$PAIR2_EXT" | wc -l)
    if [[ "$r1files" != "$r2files" ]]; then
	die "Number of $PAIR1_EXT files is different from $PAIR2_EXT [$r1files vs $r2files]."
    fi
fi

n_dense=$(find -L $INPUT -mindepth 2 -maxdepth 6 -name "*_dense.matrix" | wc -l)
if [[ $n_dense -gt 0 ]]; then
    /bin/rm $(find -L ${INPUT} -mindepth 2 -maxdepth 6 -name "*_dense.matrix")
fi
SAMPLE_NAME=$(find -L ${INPUT} -mindepth 2 -maxdepth 6 -name "*.matrix")
SAMPLE_NAME="${SAMPLE_NAME%_*}"
SAMPLE_NAME=$(basename "$SAMPLE_NAME")


##################
## Run HiCPack ##
##################
if [[ -z ${MAKE_OPTS} ]]; then
    MAKE_OPTS="mapping proc_hic quality_checks bg_model visualization"
fi
if [ $CLUSTER == 0 ]; then
    echo "Run ${SOFT} "${VERSION}
    make --file ${SCRIPTS_PATH}/Makefile CONFIG_FILE=${CONF} CONFIG_SYS=$INSTALL_PATH"/config-system.txt" SAMPLE_NAME=${SAMPLE_NAME} init 2>&1
    make --file ${SCRIPTS_PATH}/Makefile CONFIG_FILE=${CONF} CONFIG_SYS=$INSTALL_PATH"/config-system.txt" SAMPLE_NAME=${SAMPLE_NAME} ${MAKE_OPTS} 2>&1
else
    echo "Run ${SOFT} "${VERSION}" parallel mode"
    if [[ $MAKE_OPTS != "" ]]
    then
	MAKE_OPTS=$(echo ${MAKE_OPTS} | sed -e 's/ /,/g')
	make --file ${SCRIPTS_PATH}/Makefile CONFIG_FILE=${CONF} CONFIG_SYS=${INSTALL_PATH}/config-system.txt SAMPLE_NAME=${SAMPLE_NAME} MAKE_OPTS=${MAKE_OPTS} make_cluster_script 2>&1
    else
    	make --file ${SCRIPTS_PATH}/Makefile CONFIG_FILE=${CONF} CONFIG_SYS=${INSTALL_PATH}/config-system.txt SAMPLE_NAME=${SAMPLE_NAME} make_cluster_script 2>&1
    fi
fi


#make --file $SCRIPTS_PATH/Makefile CONFIG_FILE=$CONF CONFIG_SYS=$INSTALL_PATH"/config-system.txt" bg_model