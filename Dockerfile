FROM    ubuntu:latest

#TZ "fix" to build ubuntu image
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

#Update & Install required applications
#RUN apt-get update &&\
RUN DEBIAN_FRONTEND="noninteractive" apt-get update &&\
    apt-get upgrade -y &&\
    apt-get install apache2 apache2-utils subversion libsvn-dev libapache2-mod-svn curl rsync -y &&\
    apt-get install procps iftop atop htop nmon dstat ioping -y &&\
    apt-get clean

#Enable/Disable Apache features
RUN a2enmod dav_svn &&\
    a2dismod autoindex -f &&\
    a2dismod dir -f &&\
    a2dismod env -f &&\
    a2enmod status -f &&\
    a2dismod setenvif -f 
#    a2enmod status &&\
#    a2enmod remoteip &&\
#    a2dismod mpm_event &&\
#    a2enmod mpm_worker

#Create service user (not implmented yet)
RUN useradd --home-dir /home/svnadm --comment "SVN Admin User for customer" --create-home svnadm &&\
    usermod -g svnadm -G svnadm www-data

#Create directories
RUN mkdir -p /etc/svn &&\
    mkdir -p /var/log/svnsync

#Fix Module errors
COPY ./fixes/dav.load /etc/apache2/mods-available/dav.load

#Change security
COPY ./fixes/security.conf /etc/apache2/conf-available/security.conf

#Keep robots away
COPY ./fixes/robots.txt /var/www/html/robots.txt 

#Go nuts and enable 8000 concurrent sessions - keep antropy in eye -cat /proc/sys/kernel/random/entropy_avail
COPY ./fixes/mpm_worker.conf /etc/apache2/mods-available/mpm_worker.conf
#COPY ./fixes/mpm_event.conf /etc/apache2/mods-available/mpm_event.conf

#Change defaults (e.g. global timeouts)
COPY ./svn_config/000-default.conf /etc/apache2/sites-available/000-default.conf

#Copy files
COPY ./svn_config/* /home/svnadm/

#Set file system permissions
RUN  chown svnadm:svnadm /var/log/svnsync

#Add entrypoint
ADD svn-entrypoint.sh /home/svnadm/svn-entrypoint.sh
RUN chmod +x /home/svnadm/svn-entrypoint.sh
WORKDIR /home/svnadm
ENTRYPOINT ["./svn-entrypoint.sh"]

#VOLUME ["/var/www/svn"]
EXPOSE 80/tcp
