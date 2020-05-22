#!/bin/bash

set -e -x

BASEDIR=$(pwd)
APPNAME=OPENPAAS-IEDA-WEB-5.0
APPUSER=$(echo $USER)
APPDIR=$(eval echo ~$USER)

##################################
# argument check
##################################
input_file=$1
if [ -z $1 ]; then
  echo "input path and file name of OPENPAAS-IEDA-WEB-v5.0.tar"
  echo " ex) ~/Downloads/OPENPAAS-IEDA-WEB-5.0.tar"
  exit 1
fi

echo -e "check ${input_file} exist"
if [ ! -f $input_file ]; then
  echo "${input_file} is not found"
  exit 1
fi

check_file=$(basename $input_file)
if [[ "${APPNAME}.tar.gz" != "$check_file" && "${APPNAME}.tar" != "$check_file" && "${APPNAME}.zip" != "$check_file" ]]; then
  echo "$input_file is not $APPNAME"
  exit 1
fi

mysql_password=$2
if [ -z $2 ]; then
  echo "input mysql password"
  exit 1
fi

DOWNLOADDIR=~/Downloads
if [ ! -d $DOWNLOADDIR ]; then
  mkdir -p $DOWNLOADDIR
fi

sudo apt-get update

##################################
# INSTALL BOSH-INIT AND BOSH_CLI
##################################
if type -p 'bosh'; then
  _bosh='bosh'
fi

echo "Installation is start" > install.log

if [[ -z "$_bosh" ]]; then
  echo -e "bosh dependency install"
  sudo apt-get install -y build-essential zlibc zlib1g-dev ruby ruby-dev openssl libxslt-dev libxml2-dev libssl-dev libreadline6 libreadline6-dev libyaml-dev libsqlite3-dev sqlite3
  sudo apt-get install make
  sudo mv $BASEDIR/bosh /usr/local/bin/bosh
fi
wait

version="$(bosh -v 2>&1 | awk '{print $2}')"
echo "Bosh_cli version: ${version} is installed" >> install.log



##################################
# INSTALL JAVA
##################################
if type -p java; then
  _java=java
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
  _java="$JAVA_HOME/bin/java"
else
  _java=java

  echo -e "java install"
  echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main" | sudo tee /etc/apt/sources.list.d/webupd8team-java.list
  echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main" | sudo tee -a /etc/apt/sources.list.d/webupd8team-java.list
  sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886
  sudo apt-get update
  echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | sudo debconf-set-selections
  sudo apt-get -y install oracle-java8-installer
fi

version=$("$_java" -version 2>&1 | awk -F '"' '/version/ {print $2}')

if [[ "$version" > "1.7" ]]; then
  echo "java version: ${version} is installed" >> install.log
else
  echo "Installed java version is ${version}. java version must be at least 1.8"
  echo "Please remove installed java and reinstall the OPENPAAS-IEDA-WEB"
  exit 1
fi

##################################
# INSTALL MAVEN
##################################
if type -p 'mvn'; then
  _mvn='mvn'
fi

if [[ -z "$_mvn" ]]; then
  _mvn='mvn'
  echo -e "maven install"
  sudo apt-get -y install maven
fi

version=$("$_mvn" -version 2>&1 | awk '{print $3}')
echo "maven version: ${version:0:5} is installed" >> install.log

##################################
# INSTALL MYSQL
##################################
if type -p mysql; then
  version="$(mysql --version 2>&1 | awk '{print $5}')"
else
  echo -e "mysql install "

  export DEBIAN_FRONTEND="noninteractive"

  sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $mysql_password"
  sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $mysql_password"
  sudo apt-get -y install mysql-server

  version="$(mysql --version 2>&1 | awk '{print $5}')"

  if [[ "${version::-1}" < "5.5" ]]; then
    # setup innodb
    echo -e "setup innodb_file_format"
    sudo sed -i "44s/.*/\n\n\n/g" /etc/mysql/my.cnf
    sudo sed -i "45s/.*/innodb_file_per_table/g" /etc/mysql/my.cnf
    sudo sed -i "46s/.*/innodb_file_format = Barracuda/g" /etc/mysql/my.cnf

    sudo service mysql stop
    sudo service mysql start
  fi
fi

echo "mysql version: ${version::-1} is installed" >> install.log

##################################
# INSTALL OPENPAAS-IEDA-WEB
##################################
echo -e "Install $APPNAME"

if [[ "${APPNAME}.tar.gz" == "$check_file" ]]; then
  tar -C $APPDIR -xvzf ${input_file}
fi
if [[ "${APPNAME}.tar" == "$check_file" ]]; then
  tar -C $APPDIR -xvf ${input_file}
fi
if [[ "${APPNAME}.zip" == "$check_file" ]]; then
  unzip ${input_file} -d $APPDIR 
fi

if [ ! -f $APPDIR/$APPNAME/application.properties ]; then  
  cp $APPDIR/$APPNAME/OPENPAAS-IEDA-CONTROLLER/src/main/resources/application.properties $APPDIR/$APPNAME


  sed -i "22s/.*/spring.datasource.url=jdbc:mysql:\/\/localhost\/ieda?useUnicode=true\&charaterEncoding=utf-8/g" $APPDIR/$APPNAME/OPENPAAS-IEDA-CONTROLLER/src/main/resources/application.properties
  sed -i "25s/.*/spring.datasource.password=$mysql_password/g" $APPDIR/$APPNAME/OPENPAAS-IEDA-CONTROLLER/src/main/resources/application.properties
  
  sed -i "32s/.*/\#spring.datasource.schema=\/home\/$APPUSER\/$APPNAME\/src\/main\/resources\/schema.sql/g" $APPDIR/$APPNAME/OPENPAAS-IEDA-CONTROLLER/src/main/resources/application.properties

  sed -i "1s/.*/\#create database if not exists ieda default character set utf8 collate utf8_general_ci;/g" $APPDIR/$APPNAME/OPENPAAS-IEDA-CONTROLLER/src/main/resources/schema.sql
  sed -i "3s/.*/\#use ieda;/g" $APPDIR/$APPNAME/OPENPAAS-IEDA-CONTROLLER/src/main/resources/schema.sql
  
  if [ $3 == "delete" ]; then
    echo "drop database ieda;" | mysql -uroot -p$mysql_password
  fi

  echo "create database if not exists ieda default character set utf8 collate utf8_general_ci;" | mysql -uroot -p$mysql_password
  echo "use ieda;" | mysql -uroot -p$mysql_password ieda

  mysql -uroot -p$mysql_password ieda < $APPDIR/$APPNAME/OPENPAAS-IEDA-CONTROLLER/src/main/resources/schema.sql
  mysql -uroot -p$mysql_password ieda < $APPDIR/$APPNAME/OPENPAAS-IEDA-CONTROLLER/src/main/resources/import.sql


fi

##################################
# BUILD MAVEN OPENPAAS-IEDA-WEB
##################################
echo -e "build $APPNAME"
cd $APPDIR/$APPNAME
mvn -Djava.security.egd=file:/dev/./urandom -Dspring.config.location=$APPDIR/$APPNAME/OPENPAAS-IEDA-COMMON-SERVICE/src/main/resources/application.properties package
mvn_result=$?

if [ $mvn_result -ne 0 ]; then
  echo "Maven build is failed"
  exit 1
fi

##################################
# REGIST WEB SERVICE AND 
# SET LOGROTATE
##################################
chmod 755 -R $BASEDIR/*
chmod 644 $BASEDIR/deployerlog
sed -i "10s/.*/\	create 640 $APPUSER adm/g" $BASEDIR/deployerlog
sed -i "13s/.*/\    cd \-P \/home\/$APPUSER\/$APPNAME/g" $BASEDIR/pds
sed -i "35s/.*/\    cd \-P \/home\/$APPUSER\/$APPNAME/g" $BASEDIR/pds

mv $BASEDIR/deployer $APPDIR/$APPNAME/
sudo mv $BASEDIR/pds /usr/local/bin/
sudo mv $BASEDIR/deployerlog /etc/logrotate.d
sudo chown root:root /etc/logrotate.d/deployerlog
sudo mkdir -p /var/log/deployer
sudo chown $APPUSER:adm /var/log/deployer

echo -e "Installation is complete."
echo -e "A reboot of the system is required!!"
