FROM    debian:latest

#Update & Install required applications
RUN apt-get update &&\
    apt-get upgrade -y &&\
    apt-get install apache2 apache2-utils subversion libsvn-dev libapache2-mod-svn haveged htop -y &&\
    apt-get clean

#Enable Apache features
RUN a2enmod dav &&\
    a2enmod dav_svn &&\
    a2enmod deflate &&\
    a2enmod status &&\
    a2dismod mpm_event &&\ 
    a2enmod mpm_worker
#    a2enmod cache &&\
#    a2enmod cache_disk

#Create service user (not implmented yet)
RUN useradd --home-dir /home/svnadm --comment "SVN Admin User for customer" --create-home svnadm &&\
    usermod -g svnadm -G svnadm www-data

#Create directories
RUN mkdir -p /etc/svn &&\
    mkdir -p /var/log/svnsync

#Fix Module errors
COPY ./fixes/dav.load /etc/apache2/mods-available/dav.load

#Go nuts and enable 8000 concurrent sessions - keep antropy in eye -cat /proc/sys/kernel/random/entropy_avail
COPY ./fixes/dav.load /etc/apache2/mods-available/mpm_worker.conf

#Remove default website
#RUN rm -rf /var/www/html
#RUN unlink /etc/apache2/sites-available/000-default.conf

#Change defaults (e.g. global timeouts)
COPY ./svn_config/000-default.conf /etc/apache2/sites-available/000-default.conf

#Enable Compression
#COPY ./svn_config/deflate.conf /etc/apache2/mods-available/deflate.conf
#COPY ./svn_config/dav_svn /etc/apache2/mods-available/dav_svn.conf
COPY ./svn_config/* /home/svnadm/

#Set file system permissions
#RUN  chown svnadm:svnadm /etc/apache2/mods-available/dav_svn.conf
RUN  chown svnadm:svnadm /var/log/svnsync

#Add entrypoint
ADD svn-entrypoint.sh /home/svnadm/svn-entrypoint.sh
RUN chmod +x /home/svnadm/svn-entrypoint.sh
WORKDIR /home/svnadm
ENTRYPOINT ["./svn-entrypoint.sh"]

#VOLUME ["/var/www/svn"]
EXPOSE 80/tcp
