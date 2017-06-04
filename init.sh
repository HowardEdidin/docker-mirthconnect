#!/bin/bash
readonly AWS_METADATA_SERVICE_URL="http://169.254.169.254/latest/meta-data"
readonly AVAILABILITY_ZONE=$(wget -T 3 -t 1 -q -O - "${AWS_METADATA_SERVICE_URL}/placement/availability-zone")
IS_AWS=false
if [[ $? -eq 0 ]]; then
  IS_AWS=true
  export AWS_DEFAULT_REGION=$(echo ${AVAILABILITY_ZONE} | sed -E 's/^"?(.*?)([0-9]+)[a-z]*"?$/\1\2/')
fi

function get_param() {
  param=""
  ssm_param=$(aws ssm get-parameters --names $1 --with-decryption | jq -r '.Parameters[0].Value' | tr -d '[:space:]')
  [[ $? -eq 0 ]] && [[ -n "${ssm_param}" ]] && [[ ! "${ssm_param}" == "null" ]] && param=$ssm_param
}

function run_mirth_command() {
  /opt/mirthconnect/mccommand -u ${MIRTH_ADMIN_USERNAME} -p ${MIRTH_ADMIN_PASSWORD} -s $1
  sleep 2
}

get_param 'MIRTH_MYSQL_USERNAME'
MIRTH_MYSQL_USERNAME=${param:-mirth}
get_param 'MIRTH_MYSQL_PASSWORD'
MIRTH_MYSQL_PASSWORD=${param:-password}
get_param 'MIRTH_MYSQL_DBNAME'
MIRTH_MYSQL_DBNAME=${param:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)}
get_param 'MIRTH_ADMIN_USERNAME'
MIRTH_ADMIN_USERNAME=${param:-admin}
get_param 'MIRTH_ADMIN_PASSWORD'
MIRTH_ADMIN_PASSWORD=${param:-secure123}
get_param 'MIRTH_MYSQL_HOST'
MIRTH_MYSQL_HOST=${param:-mysql}
get_param 'MIRTH_MYSQL_PORT'
MIRTH_MYSQL_PORT=${param:-3306}

sed -i.bak "s/^database =.*/database = mysql/g" /opt/mirthconnect/conf/mirth.properties
sed -i.bak "s/^database\.url =.*/database.url = jdbc:mysql:\/\/${MIRTH_MYSQL_HOST}:${MIRTH_MYSQL_PORT}\/${MIRTH_MYSQL_DBNAME}/g" /opt/mirthconnect/conf/mirth.properties
sed -i.bak "s/^database\.username =.*/database.username = ${MIRTH_MYSQL_USERNAME}/g" /opt/mirthconnect/conf/mirth.properties
sed -i.bak "s/^database\.password =.*/database.password = ${MIRTH_MYSQL_PASSWORD}/g" /opt/mirthconnect/conf/mirth.properties

mirth_pw_change_script=$(mktemp)
cat <<EOS >$mirth_pw_change_script
user changepw ${MIRTH_ADMIN_USERNAME} ${MIRTH_ADMIN_PASSWORD}
EOS

import_channels_script=$(mktemp)
find /opt/import -type f -name '*.xml' | grep -v -E 'global_scripts.xml$|code_templates' | xargs -n 1 echo import | sed 's/$/ force/g' >${import_channels_script}
mirth_import_script=$(mktemp)
cat <<EOS >$mirth_import_script
importcodetemplates /opt/import/code_templates.xml
importscripts /opt/import/global_scripts.xml
deploy
EOS

(
  sleep 120
  /opt/mirthconnect/mccommand -u ${MIRTH_ADMIN_USERNAME} -p admin -s $mirth_pw_change_script
  sleep 3
  run_mirth_command $import_channels_script
  cat $import_channels_script
  run_mirth_command $mirth_import_script
  ! ${IS_AWS} && mysql -h ${MIRTH_MYSQL_HOST} -u${MIRTH_MYSQL_USERNAME} -p"${MIRTH_MYSQL_PASSWORD}" ${MIRTH_MYSQL_DBNAME} -e "insert into person_preference (PERSON_ID,NAME,VALUE) values (1,'firstlogin','false');"
) &
sleep 10 && mysql -h ${MIRTH_MYSQL_HOST} -u${MIRTH_MYSQL_USERNAME} -p"${MIRTH_MYSQL_PASSWORD}" -e "create database ${MIRTH_MYSQL_DBNAME};"
sleep 60 && exec /opt/mirthconnect/mcserver
