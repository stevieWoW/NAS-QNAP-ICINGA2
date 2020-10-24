#!/bin/sh
#
#
PLUGIN_NAME="nas"
PLUGIN_VERSION="2020.10.19"
PRINTINFO=`printf "\n%s, version %s\n \n" "$PLUGIN_NAME" "$PLUGIN_VERSION"`
#
# if nothing was declared
PORT=22
WARNING=80
CRITICAL=90
### Icinga exit codes
###
EXIT_OK=0
EXIT_WARN=1
EXIT_CRIT=2
EXIT_UNKN=3

###############################################################################
###############################################################################
Usage() {
  echo "$PRINTINFO"
  echo "Usage: $0 [OPTIONS]
Option  GNU long option         Meaning
------  --------------- -------
 
 -q     --help          Show this message
 -v     --version       Print version information and exit
 -h     --hostname      set hostname/IP     
 -u     --username      set username
 -p     --port          set Port default(22)
 -c     --critical      set critical value
 -w     --warning       set warning value
 -m     --mode          CAPACITY,BACKUP,VOLUME,SYSTEMP
"
}

###############################################################################
##
##
##                                  Functions
##
##
###############################################################################

capacitycheck(){
    _text=$(ssh ${USERNAME}@${HOSTNAME} -T -p ${PORT} <<ENDSSH
getsysinfo vol_totalsize 0 && echo "-"
getsysinfo vol_freesize 0
ENDSSH
)
    _text=`echo $_text | sed 's/ //g'`
    _total=`echo ${_text} | awk -F- '{print $1}'`
    _free=`echo ${_text} | awk -F- '{print $2}'`

    _percent=$( converttoGB ${_total} ${_free} )
    _output="Capacity "
  

    if [ ${_percent} -le ${WARNING} ]
    then
        _rc=${EXIT_OK}
        _status="OK"
    elif [ ${_percent} -ge ${CRITICAL} ]
    then
        _rc=${EXIT_CRIT}
        _status="CRITICAL"
    else
        _rc=${EXIT_WARN}
        _status="WARNING"
    fi


    _return=${_return}$( mergetoicingatext "${_output} - ${_status}" "Used(%)" "${_percent}" "%" "${WARNING}" "${CRITICAL}" "0" "100" )
    echo $_return
    exit ${_rc}
}

###############################################################################
###############################################################################
backupcheck(){
    BACKUPSTEVIESBLOG=`ssh ${USERNAME}@${HOSTNAME} -p ${PORT} cat /share/homes/rtf/steviesblog/backup/backup.log`
    BACKUPKEYPASS=`ssh ${USERNAME}@${HOSTNAME} -p ${PORT} cat /share/homes/rtf/pass/backup.log`

    STEVIESBLOG=`echo "${BACKUPSTEVIESBLOG}" | awk -F/ '{print $9}'`
    KEYPASS=`echo "${BACKUPKEYPASS}" | awk -F/ '{print $4}'`
    echo "${STEVIESBLOG}+${KEYPASS} | 'test'=20%;70;80;0;100; 'test2'=50%;70;80;0;100"
    exit ${EXIT_OK}
}

###############################################################################
###############################################################################
volumecheck(){
    _text=$(ssh ${USERNAME}@${HOSTNAME} -T -p ${PORT} <<ENDSSH
getsysinfo vol_desc 0 && echo " - "
getsysinfo vol_status 0
ENDSSH
)
    _status=`echo ${_text} | awk -F\- '{print $2}' | sed 's/ //g'`

    if [ "${_status}" = "Ready" ]
    then 
        _rc=${EXIT_OK}
    else
        _rc=${EXIT_CRIT}
    fi
    
    echo ${_text}
    exit ${_rc}
}

###############################################################################
###############################################################################
hdtempscheck(){
    _i=1
    _num=$(( $1 + 1))
    _return=
    _output="HDTEMP"

    while [ ${_i} -lt ${_num} ]
    do

    _text=$(ssh ${USERNAME}@${HOSTNAME} -T -p ${PORT} <<ENDSSH
getsysinfo hdtmp ${_i}
ENDSSH
)
        _temp=`echo ${_text} | awk '{print $1}'`
        _return=${_return}$( mergetoicingatext "${_output}" "HD ${_i} Temp(C°)" "${_temp}" "" "${WARNING}" "${CRITICAL}" "0" "100" )
        if [ ${_temp} -le ${WARNING} ]
        then
            _rc=${EXIT_OK}
            # do not override higher status
            if [ "${_status}" != "CRITICAL" -a "${_status}" != "WARNING" ]
            then
                _status="OK"
            fi
        elif [ ${_temp} -ge ${CRITICAL} ]
        then
            _rc=${EXIT_CRIT}
            _status="CRITICAL"
        else
            _rc=${EXIT_WARN}
            # do not override higher status
            if [ "${_status}" != "CRITICAL" ]
            then
                _status="WARNING"
            fi
        fi

        _output="NONE"
        true $((_i=_i+1))
    done
    echo ${_return} | sed "s/HDTEMP/HDTEMP - ${_status}/"
    exit ${_rc}
}
###############################################################################
###############################################################################
systempcheck(){
_text=$(ssh ${USERNAME}@${HOSTNAME} -T -p ${PORT} <<ENDSSH
getsysinfo systmp
ENDSSH
)

    _temp=`echo ${_text} | awk '{print $1}'`
    _output="Sys Temperature "
  
    if [ ${_temp} -le ${WARNING} ]
    then
        _rc=${EXIT_OK}
        _status="OK"
    elif [ ${_temp} -ge ${CRITICAL} ]
    then
        _rc=${EXIT_CRIT}
        _status="CRITICAL"
    else
        _rc=${EXIT_WARN}
        _status="WARNING"
    fi

    _return=${_return}$( mergetoicingatext "${_output} - ${_status}" "Temp(C°)" "${_temp}" "" "${WARNING}" "${CRITICAL}" "0" "100" )
    echo $_return
    exit ${_rc}
}
###############################################################################
###############################################################################
hddsmartcheck(){
    _i=1
    _num=$(( $1 + 1))
    _return=
    _output="PLHOLDER"

    while [ ${_i} -lt ${_num} ]
    do

    _text=$(ssh ${USERNAME}@${HOSTNAME} -T -p ${PORT} <<ENDSSH
getsysinfo hdsmart ${_i}
ENDSSH
)
        _smart=`echo ${_text}`

        _return=${_return}$( mergetoicingatext "${_output}" "HD ${_i} Smart" "${_smart}" )
        if [ "${_smart}" = "GOOD" ]
        then
            if [ "${_smart}" != "${EXIT_CRIT}" ]
            then
                _rc=${EXIT_OK}
            fi
        else
            _rc=${EXIT_CRIT}
        fi

        _output="NONE"
        true $((_i=_i+1))
    done
    echo ${_return} | sed "s/PLHOLDER/HD SMART Status - ${_smart}/"
    exit ${_rc}
}
###############################################################################
###############################################################################
mergetoicingatext(){
    _output=${1}
    _label=${2}
    _value=${3}
    _uom=${4}
    _warn=${5}
    _crit=${6}
    _min=${7}
    _max=${8}

    if [ "${_output}" = "NONE" ]
    then
        echo "'${_label}'=${_value}${_uom};${_warn};${_crit};${_min};${_max} "
    else
        echo "${_output} | '${_label}'=${_value}${_uom};${_warn};${_crit};${_min};${_max} "
    fi
}

###############################################################################
###############################################################################

converttoGB(){

    _total=$1
    _free=$2

    #found here: https://stackoverflow.com/questions/45616580/converting-kb-and-gb-to-mb-in-bash
    _totalmb=$(awk 'BEGIN{ FS=OFS="," }{ s=substr($1,1,length($1)-1); u=substr($1,length($1)-1); 
    if(u=="TB") $1=(s*1024); else if(u=="MB") $1=(s/1024); else if(u=="GB") $1=(s/1); }1' <<EOF | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}'
${_total}
EOF
)

    _freemb=$(awk 'BEGIN{ FS=OFS="," }{ s=substr($1,1,length($1)-1); u=substr($1,length($1)-1); 
        if(u=="TB") $1=(s*1024); else if(u=="MB") $1=(s/1024); else if(u=="GB") $1=(s/1); }1' <<EOF | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}'
${_free}
EOF
)

    _percent=$(( (_freemb * 100) / _totalmb  ))

    echo ${_percent}
}

###############################################################################
##
##
##                                  MAIN PART
##
##
###############################################################################



OPTS=`getopt  -o qvh:u:pc:w:m: -l hostname:,username:,critical:,warning:,port,mode:,help,version -- "$@"`
eval set -- "$OPTS"

while :
do
    case $1 in
        -q|--help)
            Usage; exit 0;;
        -v|--version)
            echo "$PRINTINFO"; exit 0;;
        -u|--username)
            USERNAME="$2"; shift 2; ;;
        -h|--hostname)
            HOSTNAME="$2"; shift 2; ;;
        -p|--port)
            PORT="$2"; shift 2; ;;
        -c|--critical)
            CRITICAL="$2"; shift 2; ;;
        -w|--warning)
            WARNING="$2"; shift 2; ;;
        -m|--mode)
            MODE="$2"; shift 2; ;;
        --)
            # no more arguments to parse
            shift ; break ;;
        *)
            printf "\nUnrecognized option %s\n\n" "$1" ; Usage ; exit 1 ;;
    esac 
done

if [ -z ${USERNAME} ] && [ -z ${HOSTNAME} ];
then
    printf "\nHostname or Username not defined\n"
    exit ${EXIT_CRIT} 
else

###############################################################################
# collect some  Infos about that NAS
INFO=`ssh ${USERNAME}@${HOSTNAME} -T -p ${PORT}`<<EOF
echo "Model:" && getsysinfo model && echo "\n"
echo "HDNum:" && getsysinfo hdnum && echo "\n"
echo "SysVolNum:" && getsysinfo sysvolnum && echo "\n"
echo "SysFanNum:" && getsysinfo sysfannum && echo "\n"
EOF

#strip this information into variables
MODEL=`echo $INFO | grep Model | awk -F: '{print $2}'`
DRIVESNUM=`echo $INFO | grep HDNum | awk -F: '{print $2}'`
VOLUMENUM=`echo $INFO | grep SysVolNum | awk -F: '{print $2}'`
FANNUN=`echo $INFO | grep SysFanNum | awk -F: '{print $2}'`
#
#
###############################################################################
    case ${MODE} in
        "CAPACITY")
            capacitycheck
            ;;
        "BACKUP")
            backupcheck
            ;;
        "VOLUME")
            volumecheck
            ;;
        "HDTEMPS")
            hdtempscheck ${DRIVESNUM}
            ;;
        "SYSTEMP")
            systempcheck
            ;;
        "HDDSTATUS")
            hddsmartcheck ${DRIVESNUM}
            ;;
        *)
            echo "no MODE selected"
            exit ${EXIT_CRIT}
            ;;
    esac
    
fi

printf "\n something went wrong with the script\n"
exit ${EXIT_UNKN}
